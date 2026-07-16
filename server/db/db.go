// Package db handles database storage and management for the VPN server using SQLite.
package db

import (
	"database/sql"
	"fmt"
	"time"

	_ "modernc.org/sqlite" // Pure-Go SQLite driver to facilitate compilation without CGO
)

// User represents a VPN server account.
type User struct {
	ID          int64
	Username    string
	AccessKey   string
	Role        string // "owner", "admin", "user"
	DeviceLimit int
	CreatedAt   time.Time
}

// Device represents a registered client device.
type Device struct {
	ID        int64
	UserID    int64
	HWID      string
	LastSeen  time.Time
}

// Store wraps the database connection pool.
type Store struct {
	db *sql.DB
}

// NewStore initializes a new SQLite connection and runs migrations.
func NewStore(dbPath string) (*Store, error) {
	// Enable modernc sqlite driver
	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	s := &Store{db: db}
	if err := s.migrate(); err != nil {
		db.Close()
		return nil, fmt.Errorf("failed to run migrations: %w", err)
	}

	return s, nil
}

// Close closes the database connection.
func (s *Store) Close() error {
	return s.db.Close()
}

func (s *Store) migrate() error {
	// Enable Foreign Key constraints
	_, err := s.db.Exec("PRAGMA foreign_keys = ON;")
	if err != nil {
		return err
	}

	// Create users table
	usersSchema := `
	CREATE TABLE IF NOT EXISTS users (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		username TEXT NOT NULL,
		access_key TEXT NOT NULL UNIQUE,
		role TEXT NOT NULL CHECK(role IN ('owner', 'admin', 'user')),
		device_limit INTEGER NOT NULL DEFAULT 1 CHECK(device_limit >= 1 AND device_limit <= 5),
		created_at DATETIME NOT NULL
	);`
	if _, err := s.db.Exec(usersSchema); err != nil {
		return err
	}

	// Create devices table for HWID tracking
	devicesSchema := `
	CREATE TABLE IF NOT EXISTS devices (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		user_id INTEGER NOT NULL,
		hwid TEXT NOT NULL,
		last_seen DATETIME NOT NULL,
		FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
		UNIQUE(user_id, hwid)
	);`
	if _, err := s.db.Exec(devicesSchema); err != nil {
		return err
	}

	// Create index on access_key for quick lookups
	_, err = s.db.Exec("CREATE INDEX IF NOT EXISTS idx_users_key ON users(access_key);")
	return err
}

// CreateUser inserts a new user into the database.
func (s *Store) CreateUser(username, accessKey, role string, deviceLimit int) (*User, error) {
	query := `INSERT INTO users (username, access_key, role, device_limit, created_at)
			  VALUES (?, ?, ?, ?, ?) RETURNING id, created_at`
	
	now := time.Now()
	var id int64
	var createdAt time.Time

	err := s.db.QueryRow(query, username, accessKey, role, deviceLimit, now).Scan(&id, &createdAt)
	if err != nil {
		return nil, err
	}

	return &User{
		ID:          id,
		Username:    username,
		AccessKey:   accessKey,
		Role:        role,
		DeviceLimit: deviceLimit,
		CreatedAt:   createdAt,
	}, nil
}

// GetUserByKey retrieves a user by their access key.
func (s *Store) GetUserByKey(accessKey string) (*User, error) {
	query := `SELECT id, username, access_key, role, device_limit, created_at FROM users WHERE access_key = ?`
	var u User
	err := s.db.QueryRow(query, accessKey).Scan(&u.ID, &u.Username, &u.AccessKey, &u.Role, &u.DeviceLimit, &u.CreatedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	} else if err != nil {
		return nil, err
	}
	return &u, nil
}

// DeleteUser deletes a user by their ID.
func (s *Store) DeleteUser(id int64) error {
	_, err := s.db.Exec("DELETE FROM users WHERE id = ?", id)
	return err
}

// GetDevicesForUser retrieves all registered devices for a user.
func (s *Store) GetDevicesForUser(userID int64) ([]Device, error) {
	query := `SELECT id, user_id, hwid, last_seen FROM devices WHERE user_id = ?`
	rows, err := s.db.Query(query, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var list []Device
	for rows.Next() {
		var d Device
		if err := rows.Scan(&d.ID, &d.UserID, &d.HWID, &d.LastSeen); err != nil {
			return nil, err
		}
		list = append(list, d)
	}
	return list, nil
}

// RegisterDevice registers a device HWID under a user, updating last_seen if already present.
// Returns an error if the user has reached their maximum device limit.
func (s *Store) RegisterDevice(userID int64, hwid string) error {
	// Start transaction to prevent race conditions in device verification
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	// 1. Get user details for device limits and role
	var limit int
	var role string
	err = tx.QueryRow("SELECT device_limit, role FROM users WHERE id = ?", userID).Scan(&limit, &role)
	if err != nil {
		return err
	}
	if role == "admin" {
		limit = 1
	}

	// 2. Count registered devices
	var count int
	err = tx.QueryRow("SELECT COUNT(*) FROM devices WHERE user_id = ?", userID).Scan(&count)
	if err != nil {
		return err
	}

	// 3. Check if device is already registered
	var exists bool
	err = tx.QueryRow("SELECT EXISTS(SELECT 1 FROM devices WHERE user_id = ? AND hwid = ?)", userID, hwid).Scan(&exists)
	if err != nil {
		return err
	}

	now := time.Now()
	if exists {
		// Update last seen
		_, err = tx.Exec("UPDATE devices SET last_seen = ? WHERE user_id = ? AND hwid = ?", now, userID, hwid)
		if err != nil {
			return err
		}
	} else {
		// Device is new, verify limits
		if count >= limit {
			return fmt.Errorf("device limit exceeded (%d/%d)", count, limit)
		}
		// Register new device
		_, err = tx.Exec("INSERT INTO devices (user_id, hwid, last_seen) VALUES (?, ?, ?)", userID, hwid, now)
		if err != nil {
			return err
		}
	}

	return tx.Commit()
}

// ResetUserDevices clears all registered devices for a user.
func (s *Store) ResetUserDevices(userID int64) error {
	_, err := s.db.Exec("DELETE FROM devices WHERE user_id = ?", userID)
	return err
}

// ListUsers lists all registered users.
func (s *Store) ListUsers() ([]User, error) {
	query := `SELECT id, username, access_key, role, device_limit, created_at FROM users`
	rows, err := s.db.Query(query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var list []User
	for rows.Next() {
		var u User
		if err := rows.Scan(&u.ID, &u.Username, &u.AccessKey, &u.Role, &u.DeviceLimit, &u.CreatedAt); err != nil {
			return nil, err
		}
		list = append(list, u)
	}
	return list, nil
}
