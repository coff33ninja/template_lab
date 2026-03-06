package test

import (
	"strings"
	"testing"

	"example.com/__PROJECT_SLUG__/pkg/library"
)

func TestCreateGreeting(t *testing.T) {
	value := library.CreateGreeting("dev")
	if !strings.Contains(value, "{{project_slug}}") {
		t.Fatalf("unexpected greeting: %s", value)
	}
}
