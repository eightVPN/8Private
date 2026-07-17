package db

import (
	"os"
	"testing"
)

func TestStore(t *testing.T) {
	dbFile := "test_run.db"
	defer os.Remove(dbFile)

	store, err := NewStore(dbFile)
	if err != nil {
		t.Fatalf("failed to create database store: %v", err)
	}
	defer store.Close()

	// 1. Test CreateUser
	user, err := store.CreateUser("testuser", "key_abc123", "", "user", 2, 0)
	if err != nil {
		t.Fatalf("failed to create user: %v", err)
	}

	if user.Username != "testuser" || user.Role != "user" || user.DeviceLimit != 2 {
		t.Errorf("created user properties mismatch: %+v", user)
	}

	// 2. Test GetUserByKey
	retrieved, err := store.GetUserByKey("key_abc123")
	if err != nil {
		t.Fatalf("failed to get user: %v", err)
	}

	if retrieved == nil || retrieved.ID != user.ID {
		t.Errorf("retrieved user mismatch: %+v", retrieved)
	}

	// 3. Register Device 1 (Should succeed, count = 1)
	err = store.RegisterDevice(user.ID, "hwid_device_1")
	if err != nil {
		t.Fatalf("failed to register device 1: %v", err)
	}

	// Re-register Device 1 (should succeed, count remains 1)
	err = store.RegisterDevice(user.ID, "hwid_device_1")
	if err != nil {
		t.Fatalf("failed to re-register device 1: %v", err)
	}

	// Register Device 2 (Should succeed, count = 2, limit = 2)
	err = store.RegisterDevice(user.ID, "hwid_device_2")
	if err != nil {
		t.Fatalf("failed to register device 2: %v", err)
	}

	// Register Device 3 (Should fail, count would be 3 > 2)
	err = store.RegisterDevice(user.ID, "hwid_device_3")
	if err == nil {
		t.Error("expected error due to device limit, but got nil")
	}

	// 4. Reset User Devices
	err = store.ResetUserDevices(user.ID)
	if err != nil {
		t.Fatalf("failed to reset user devices: %v", err)
	}

	// Register Device 3 (should now succeed after reset, count = 1)
	err = store.RegisterDevice(user.ID, "hwid_device_3")
	if err != nil {
		t.Fatalf("failed to register device 3 after reset: %v", err)
	}
}
