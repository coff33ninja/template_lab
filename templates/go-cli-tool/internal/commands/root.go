package commands

import (
	"errors"
	"flag"
	"fmt"

	"example.com/{{project_slug}}/pkg/version"
)

func Run(args []string) error {
	if len(args) == 0 {
		fmt.Println("Usage: {{project_slug}} <version|echo>")
		return nil
	}

	switch args[0] {
	case "version":
		fmt.Println(version.String())
		return nil
	case "echo":
		fs := flag.NewFlagSet("echo", flag.ContinueOnError)
		msg := fs.String("msg", "hello", "message to echo")
		if err := fs.Parse(args[1:]); err != nil {
			return err
		}
		fmt.Println(*msg)
		return nil
	default:
		return errors.New("unknown command: " + args[0])
	}
}
