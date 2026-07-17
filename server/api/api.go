// Package api implements the administrative REST API for the VPN server.
package api

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"

	"github.com/user/vpn8/server/db"
)

// Server handles administrative REST API requests.
type Server struct {
	store  *db.Store
	apiKey string
}

// NewServer creates a new API Server instance.
func NewServer(store *db.Store, apiKey string) *Server {
	return &Server{
		store:  store,
		apiKey: apiKey,
	}
}

// Handler returns the HTTP handler with authentication middleware.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /api/users", s.listUsers)
	mux.HandleFunc("POST /api/users", s.createUser)
	mux.HandleFunc("DELETE /api/users/{id}", s.deleteUser)
	mux.HandleFunc("POST /api/users/{id}/reset", s.resetDevices)
	mux.HandleFunc("POST /api/users/{id}/reissue-api-key", s.reissueAPIKey)
	mux.HandleFunc("POST /api/users/{id}/reissue-access-key", s.reissueAccessKey)
	mux.HandleFunc("POST /api/server/reboot", s.serverReboot)
	mux.HandleFunc("POST /api/server/wipe", s.serverWipe)

	return s.authMiddleware(mux)
}

type contextKey string
const userContextKey contextKey = "user"

func (s *Server) authMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token := r.Header.Get("X-API-Key")
		
		if token == "" {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusUnauthorized)
			_, _ = w.Write([]byte(`{"error": "Unauthorized"}`))
			return
		}

		var role string

		if token == s.apiKey {
			// System default owner
			role = "owner"
		} else {
			// Lookup user by API key
			u, err := s.store.GetUserByAPIKey(token)
			if err != nil || u == nil {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusUnauthorized)
				_, _ = w.Write([]byte(`{"error": "Unauthorized"}`))
				return
			}
			if u.Role != "owner" && u.Role != "admin" {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusForbidden)
				_, _ = w.Write([]byte(`{"error": "Forbidden"}`))
				return
			}
			role = u.Role
		}

		w.Header().Set("Content-Type", "application/json")
		
		// Add role to context
		ctx := r.Context()
		ctx = context.WithValue(ctx, userContextKey, role)
		r = r.WithContext(ctx)

		next.ServeHTTP(w, r)
	})
}

func (s *Server) listUsers(w http.ResponseWriter, r *http.Request) {
	users, err := s.store.ListUsers()
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}
	_ = json.NewEncoder(w).Encode(users)
}

type createUserRequest struct {
	Username    string `json:"username"`
	Role        string `json:"role"`
	DeviceLimit int    `json:"device_limit"`
	RateLimit   int    `json:"rate_limit"`
}

func generateAPIKey() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return fmt.Sprintf("api_%x", b)
}

func (s *Server) createUser(w http.ResponseWriter, r *http.Request) {
	var req createUserRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"error": "Invalid request body"}`))
		return
	}

	if req.Username == "" || req.Role == "" || req.DeviceLimit < 1 || req.DeviceLimit > 5 {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"error": "Invalid parameters. Role must be owner/admin/user, limit 1-5"}`))
		return
	}

	if req.Role != "owner" && req.Role != "admin" && req.Role != "user" {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"error": "Invalid role"}`))
		return
	}

	// Basic role check
	token := r.Header.Get("X-API-Key")
	var isOwner bool
	if token == s.apiKey {
		isOwner = true
	} else {
		u, _ := s.store.GetUserByAPIKey(token)
		if u != nil && u.Role == "owner" {
			isOwner = true
		}
	}

	if req.Role == "owner" && !isOwner {
		w.WriteHeader(http.StatusForbidden)
		_, _ = w.Write([]byte(`{"error": "Only owners can create new owners"}`))
		return
	}

	// Generate secure connection key prefix with 'epn_'
	accessKey := generateAccessKey()
	
	apiKey := ""
	if req.Role == "owner" || req.Role == "admin" {
		apiKey = generateAPIKey()
	}

	user, err := s.store.CreateUser(req.Username, accessKey, apiKey, req.Role, req.DeviceLimit, req.RateLimit)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}

	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(user)
}

func (s *Server) deleteUser(w http.ResponseWriter, r *http.Request) {
	idStr := r.PathValue("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"error": "Invalid user ID"}`))
		return
	}

	targetUser, err := s.store.GetUserByID(id)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		return
	}
	if targetUser == nil {
		w.WriteHeader(http.StatusNotFound)
		return
	}

	role, _ := r.Context().Value(userContextKey).(string)
	if targetUser.Role == "owner" && role != "owner" {
		w.WriteHeader(http.StatusForbidden)
		_, _ = w.Write([]byte(`{"error": "Only owners can delete owners"}`))
		return
	}

	if err := s.store.DeleteUser(id); err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}

	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(`{"status": "deleted"}`))
}

func (s *Server) reissueAPIKey(w http.ResponseWriter, r *http.Request) {
	idStr := r.PathValue("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		return
	}

	targetUser, _ := s.store.GetUserByID(id)
	if targetUser == nil {
		w.WriteHeader(http.StatusNotFound)
		return
	}

	role, _ := r.Context().Value(userContextKey).(string)
	if targetUser.Role == "owner" && role != "owner" {
		w.WriteHeader(http.StatusForbidden)
		_, _ = w.Write([]byte(`{"error": "Only owners can modify owners"}`))
		return
	}

	newAPIKey := ""
	if targetUser.Role == "owner" || targetUser.Role == "admin" {
		newAPIKey = generateAPIKey()
	}

	if err := s.store.UpdateUserAPIKey(id, newAPIKey); err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(fmt.Sprintf(`{"api_key": "%s"}`, newAPIKey)))
}

func (s *Server) reissueAccessKey(w http.ResponseWriter, r *http.Request) {
	idStr := r.PathValue("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		return
	}

	targetUser, _ := s.store.GetUserByID(id)
	if targetUser == nil {
		w.WriteHeader(http.StatusNotFound)
		return
	}

	role, _ := r.Context().Value(userContextKey).(string)
	if targetUser.Role == "owner" && role != "owner" {
		w.WriteHeader(http.StatusForbidden)
		_, _ = w.Write([]byte(`{"error": "Only owners can modify owners"}`))
		return
	}

	newAccessKey := generateAccessKey()
	if err := s.store.UpdateUserAccessKey(id, newAccessKey); err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(fmt.Sprintf(`{"access_key": "%s"}`, newAccessKey)))
}

func (s *Server) serverReboot(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(`{"status": "rebooting"}`))
	
	// Reboot async
	go func() {
		// exec.Command("reboot").Run() // actually reboot
	}()
}

func (s *Server) serverWipe(w http.ResponseWriter, r *http.Request) {
	role, _ := r.Context().Value(userContextKey).(string)
	if role != "owner" {
		w.WriteHeader(http.StatusForbidden)
		_, _ = w.Write([]byte(`{"error": "Only owners can wipe the server"}`))
		return
	}

	users, _ := s.store.ListUsers()
	for _, u := range users {
		if u.Username != "default_owner" { // Preserve default owner if exists
			s.store.DeleteUser(u.ID)
		} else {
			s.store.ResetUserDevices(u.ID)
		}
	}

	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(`{"status": "wiped"}`))
}

func (s *Server) resetDevices(w http.ResponseWriter, r *http.Request) {
	idStr := r.PathValue("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"error": "Invalid user ID"}`))
		return
	}

	if err := s.store.ResetUserDevices(id); err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}

	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(`{"status": "reset"}`))
}

func generateAccessKey() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return fmt.Sprintf("epn_%x", b)
}
