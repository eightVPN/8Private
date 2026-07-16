// Package auth implements authentication and access control for the VPN server.
package auth

import (
	"errors"
	"github.com/user/vpn8/server/db"
)

// AuthenticateResult contains authenticated user details.
type AuthenticateResult struct {
	User *db.User
}

// Authenticate verifies the client's access key, registers/updates the HWID,
// and enforces device connection quotas. It strictly overrides the limit to 1 device for Admins.
func Authenticate(store *db.Store, key string, hwid string) (*AuthenticateResult, error) {
	if key == "" {
		return nil, errors.New("access key cannot be empty")
	}
	if hwid == "" {
		return nil, errors.New("device hardware ID (HWID) cannot be empty")
	}

	user, err := store.GetUserByKey(key)
	if err != nil {
		return nil, err
	}
	if user == nil {
		return nil, errors.New("invalid access key")
	}

	// Safety enforcement: Admin keys are strictly restricted to 1 device maximum.
	if user.Role == "admin" && user.DeviceLimit != 1 {
		user.DeviceLimit = 1
	}

	// Register the client device and verify database limits
	err = store.RegisterDevice(user.ID, hwid)
	if err != nil {
		return nil, err // Returns "device limit exceeded (count/limit)" on failure
	}

	return &AuthenticateResult{User: user}, nil
}
