const output = document.getElementById("output");
const button = document.getElementById("ping");

button.addEventListener("click", () => {
  output.textContent = "pong";
});
