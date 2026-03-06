package main

import (
	"fmt"

	"example.com/{{project_slug}}/internal/jobs"
)

func main() {
	fmt.Println(jobs.Run("heartbeat"))
}
