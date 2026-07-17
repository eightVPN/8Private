package auth

import (
	"os"
	"testing"
	"github.com/user/vpn8/server/db"
)

func TestAuthenticate(t *testing.T) {
	dbFile := "test_auth_run.db"
	defer os.Remove(dbFile)

	store, err := db.NewStore(dbFile)
	if err != nil {
		t.Fatalf("failed to create store: %v", err)
	}
	defer store.Close()

	// 1. Create a regular user with device limit = 2
	_, err = store.CreateUser("user1", "user_key_1", "", "user", 2, 0)
	if err != nil {
		t.Fatalf("failed to create user: %v", err)
	}

	// 2. Create an admin user (with an input limit of 3, which must be overridden to 1 by auth engine)
	_, err = store.CreateUser("admin1", "admin_key_1", "admin_api_key_1", "admin", 3, 0)
	if err != nil {
		t.Fatalf("failed to create admin: %v", err)
	}

	// Test A: Authenticate normal user (device 1)
	res, err := Authenticate(store, "user_key_1", "hwid_u1_d1")
	if err != nil {
		t.Fatalf("auth user device 1 failed: %v", err)
	}
	if res.User.Username != "user1" {
		t.Errorf("expected user1, got %s", res.User.Username)
	}

	// Authenticate normal user (device 2) - should succeed
	_, err = Authenticate(store, "user_key_1", "hwid_u1_d2")
	if err != nil {
		t.Fatalf("auth user device 2 failed: %v", err)
	}

	// Authenticate normal user (device 3) - should fail
	_, err = Authenticate(store, "user_key_1", "hwid_u1_d3")
	if err == nil {
		t.Error("expected auth error for third device of normal user, got nil")
	}

	// Test B: Authenticate admin user (device 1) - should succeed
	resAdmin, err := Authenticate(store, "admin_key_1", "hwid_a1_d1")
	if err != nil {
		t.Fatalf("auth admin device 1 failed: %v", err)
	}
	if resAdmin.User.DeviceLimit != 1 {
		t.Errorf("expected admin device limit to be overridden to 1, got %d", resAdmin.User.DeviceLimit)
	}

	// Authenticate admin user (device 2) - should fail because admin limit is overridden to 1
	_, err = Authenticate(store, "admin_key_1", "hwid_a1_d2")
	if err == nil {
		t.Error("expected auth error for second admin device, got nil")
	}
}
