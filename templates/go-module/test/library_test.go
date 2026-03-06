package test

import (
	"strings"
	"testing"

	"example.com/{{project_slug}}/pkg/library"
)

func TestCreateGreeting(t *testing.T) {
	value := library.CreateGreeting("dev")
	if !strings.Contains(value, "{{project_slug}}") {
		t.Fatalf("unexpected greeting: %s", value)
	}
}
