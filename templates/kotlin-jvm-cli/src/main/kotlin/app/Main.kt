package app

fun main(args: Array<String>) {
    if (args.contains("--version")) {
        println("{{project_name}} 0.1.0")
        return
    }
    println("Hello from {{project_name}}")
}
