package handlers

import (
	"encoding/json"
	"net/http"

	"example.com/{{project_slug}}/internal/services"
)

func Health(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{
		"status": services.StatusMessage(),
	})
}
