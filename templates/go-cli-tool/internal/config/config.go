package config

type Config struct {
	Name string
}

func Default() Config {
	return Config{Name: "{{project_name}}"}
}
