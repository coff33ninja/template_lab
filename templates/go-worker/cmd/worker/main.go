package main

import (
	"fmt"

	"example.com/__PROJECT_SLUG__/internal/jobs"
)

func main() {
	fmt.Println(jobs.Run("heartbeat"))
}
