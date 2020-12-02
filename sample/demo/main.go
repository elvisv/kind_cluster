package main

import (
	"fmt"
	"log"
	"os"
	"net/http"
	"io/ioutil"
)

func handler(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintln(w, "Hello " + os.Getenv("DEMO_NAME") + " welcome to the Demo 1!")
	data, err := ioutil.ReadFile("/config/person.yaml")
    if err != nil {
        fmt.Fprintln(w,"File reading error")
        return
    }
    fmt.Fprintln(w,"Contents of file:" + string(data))
}

func main() {
	http.HandleFunc("/", handler)
	log.Fatal(http.ListenAndServe(":8888", nil))
}
