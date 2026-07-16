package api

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strconv"
	"testing"

	"github.com/user/vpn8/server/db"
)

func TestAPIServer(t *testing.T) {
	dbFile := "test_api_run.db"
	defer os.Remove(dbFile)

	store, err := db.NewStore(dbFile)
	if err != nil {
		t.Fatalf("failed to create store: %v", err)
	}
	defer store.Close()

	apiKey := "my_test_api_key_123"
	server := NewServer(store, apiKey)
	handler := server.Handler()

	// Helper to send HTTP requests to the handler
	sendReq := func(method, path string, body []byte, key string) *httptest.ResponseRecorder {
		req := httptest.NewRequest(method, path, bytes.NewReader(body))
		if key != "" {
			req.Header.Set("X-API-Key", key)
		}
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		return rec
	}

	// 1. Test Unauthorized access
	rec := sendReq("GET", "/api/users", nil, "wrong_token")
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 Unauthorized, got %d", rec.Code)
	}

	// 2. Test List Users (empty initially)
	rec = sendReq("GET", "/api/users", nil, apiKey)
	if rec.Code != http.StatusOK {
		t.Errorf("expected 200 OK, got %d", rec.Code)
	}
	var users []db.User
	if err := json.Unmarshal(rec.Body.Bytes(), &users); err != nil {
		t.Fatalf("failed to parse user list: %v", err)
	}
	if len(users) != 0 {
		t.Errorf("expected empty user list, got %d items", len(users))
	}

	// 3. Test Create User
	payload := []byte(`{"username": "api_user", "role": "user", "device_limit": 3}`)
	rec = sendReq("POST", "/api/users", payload, apiKey)
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 Created, got %d: %s", rec.Code, rec.Body.String())
	}
	var newUser db.User
	if err := json.Unmarshal(rec.Body.Bytes(), &newUser); err != nil {
		t.Fatalf("failed to parse new user response: %v", err)
	}
	if newUser.Username != "api_user" || newUser.Role != "user" || newUser.DeviceLimit != 3 {
		t.Errorf("created user mismatch: %+v", newUser)
	}

	// 4. Test List Users again (should contain 1 user)
	rec = sendReq("GET", "/api/users", nil, apiKey)
	if err := json.Unmarshal(rec.Body.Bytes(), &users); err != nil {
		t.Fatalf("failed to parse list after create: %v", err)
	}
	if len(users) != 1 || users[0].ID != newUser.ID {
		t.Errorf("expected 1 user in database, got %+v", users)
	}

	// 5. Test Reset User Devices
	rec = sendReq("POST", "/api/users/"+strconv.FormatInt(newUser.ID, 10)+"/reset", nil, apiKey)
	if rec.Code != http.StatusOK {
		t.Errorf("expected 200 OK for reset, got %d", rec.Code)
	}

	// 6. Test Delete User
	rec = sendReq("DELETE", "/api/users/"+strconv.FormatInt(newUser.ID, 10), nil, apiKey)
	if rec.Code != http.StatusOK {
		t.Errorf("expected 200 OK for delete, got %d", rec.Code)
	}

	// Test List Users after deletion (should be empty again)
	rec = sendReq("GET", "/api/users", nil, apiKey)
	if err := json.Unmarshal(rec.Body.Bytes(), &users); err != nil {
		t.Fatalf("failed to parse list after delete: %v", err)
	}
	if len(users) != 0 {
		t.Errorf("expected empty list after deletion, got %d items", len(users))
	}
}
