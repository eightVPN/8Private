package daemon

import (
	"net"
	"sync"
	"testing"
)

func TestIPPoolAllocate(t *testing.T) {
	pool, err := NewIPPool("10.8.0.0/16", 0)
	if err != nil {
		t.Fatalf("failed to create pool: %v", err)
	}

	seen := make(map[string]bool)
	for i := 0; i < 10; i++ {
		ip, err := pool.Allocate()
		if err != nil {
			t.Fatalf("allocation %d failed: %v", i, err)
		}

		ipStr := ip.String()
		if seen[ipStr] {
			t.Fatalf("duplicate IP allocated: %s", ipStr)
		}
		seen[ipStr] = true

		// Verify the IP is within the subnet and not the server or network address.
		if !pool.IsManaged(ip) {
			t.Fatalf("allocated IP %s is not in managed subnet", ipStr)
		}
		if ip.Equal(pool.ServerIP()) {
			t.Fatalf("allocated IP %s is the server IP", ipStr)
		}
		if ip.Equal(net.ParseIP("10.8.0.0")) {
			t.Fatal("allocated the network address 10.8.0.0")
		}
	}

	if pool.AllocatedCount() != 10 {
		t.Fatalf("expected 10 allocated, got %d", pool.AllocatedCount())
	}
}

func TestIPPoolRelease(t *testing.T) {
	pool, err := NewIPPool("10.8.0.0/16", 0)
	if err != nil {
		t.Fatalf("failed to create pool: %v", err)
	}

	ip, err := pool.Allocate()
	if err != nil {
		t.Fatalf("initial allocation failed: %v", err)
	}
	firstIP := ip.String()

	if err := pool.Release(ip); err != nil {
		t.Fatalf("release failed: %v", err)
	}

	if pool.AllocatedCount() != 0 {
		t.Fatalf("expected 0 allocated after release, got %d", pool.AllocatedCount())
	}

	// Re-allocate: should get the same IP back since the hint was reset.
	ip2, err := pool.Allocate()
	if err != nil {
		t.Fatalf("re-allocation failed: %v", err)
	}

	if ip2.String() != firstIP {
		t.Fatalf("expected re-allocated IP %s, got %s", firstIP, ip2.String())
	}
}

func TestIPPoolExhaustion(t *testing.T) {
	// Create a pool limited to exactly 3 client IPs.
	pool, err := NewIPPool("10.8.0.0/16", 3)
	if err != nil {
		t.Fatalf("failed to create pool: %v", err)
	}

	if pool.PoolSize() != 3 {
		t.Fatalf("expected pool size 3, got %d", pool.PoolSize())
	}

	for i := 0; i < 3; i++ {
		if _, err := pool.Allocate(); err != nil {
			t.Fatalf("allocation %d failed unexpectedly: %v", i, err)
		}
	}

	// The 4th allocation must fail.
	_, err = pool.Allocate()
	if err != ErrPoolExhausted {
		t.Fatalf("expected ErrPoolExhausted, got %v", err)
	}
}

func TestIPPoolServerIP(t *testing.T) {
	pool, err := NewIPPool("10.8.0.0/16", 0)
	if err != nil {
		t.Fatalf("failed to create pool: %v", err)
	}

	expected := net.ParseIP("10.8.0.1").To4()
	got := pool.ServerIP().To4()

	if !expected.Equal(got) {
		t.Fatalf("expected server IP %s, got %s", expected, got)
	}
}

func TestIPPoolIsManaged(t *testing.T) {
	pool, err := NewIPPool("10.8.0.0/16", 0)
	if err != nil {
		t.Fatalf("failed to create pool: %v", err)
	}

	tests := []struct {
		ip     string
		expect bool
	}{
		{"10.8.0.1", true},
		{"10.8.0.2", true},
		{"10.8.255.254", true},
		{"10.8.0.0", true},       // network address is in the subnet
		{"10.8.255.255", true},   // broadcast is technically in the subnet
		{"10.9.0.1", false},
		{"192.168.1.1", false},
		{"10.7.255.255", false},
	}

	for _, tt := range tests {
		ip := net.ParseIP(tt.ip)
		got := pool.IsManaged(ip)
		if got != tt.expect {
			t.Errorf("IsManaged(%s) = %v, want %v", tt.ip, got, tt.expect)
		}
	}
}

func TestIPPoolConcurrency(t *testing.T) {
	pool, err := NewIPPool("10.8.0.0/16", 1000)
	if err != nil {
		t.Fatalf("failed to create pool: %v", err)
	}

	const goroutines = 100
	var wg sync.WaitGroup
	results := make(chan string, goroutines)
	errs := make(chan error, goroutines)

	wg.Add(goroutines)
	for i := 0; i < goroutines; i++ {
		go func() {
			defer wg.Done()
			ip, err := pool.Allocate()
			if err != nil {
				errs <- err
				return
			}
			results <- ip.String()
		}()
	}

	wg.Wait()
	close(results)
	close(errs)

	for err := range errs {
		t.Fatalf("concurrent allocation failed: %v", err)
	}

	seen := make(map[string]bool)
	for ipStr := range results {
		if seen[ipStr] {
			t.Fatalf("duplicate IP from concurrent allocation: %s", ipStr)
		}
		seen[ipStr] = true
	}

	if len(seen) != goroutines {
		t.Fatalf("expected %d unique IPs, got %d", goroutines, len(seen))
	}

	if pool.AllocatedCount() != goroutines {
		t.Fatalf("expected %d allocated, got %d", goroutines, pool.AllocatedCount())
	}
}
