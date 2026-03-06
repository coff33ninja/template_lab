package test

import (
	"strings"
	"testing"

	"example.com/{{project_slug}}/internal/jobs"
)

func TestRun(t *testing.T) {
	result := jobs.Run("smoke")
	if !strings.HasSuffix(result, "::ok") {
		t.Fatalf("unexpected worker result: %s", result)
	}
}
