package jobs

func Run(name string) string {
	return "{{project_slug}}::" + name + "::ok"
}
