package handlers

import (
	"encoding/json"
	"net/http"

	"example.com/__PROJECT_SLUG__/internal/services"
)

func Health(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{
		"status": services.StatusMessage(),
	})
}
