package test

import (
	"strings"
	"testing"

	"example.com/__PROJECT_SLUG__/internal/jobs"
)

func TestRun(t *testing.T) {
	result := jobs.Run("smoke")
	if !strings.HasSuffix(result, "::ok") {
		t.Fatalf("unexpected worker result: %s", result)
	}
}
