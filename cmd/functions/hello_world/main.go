// Package main is the entry point for the hello_world lambda function
package main

import (
	"context"
	"encoding/json"
	"go-api-gateway/configuration" //nolint: gci // This is a local package
	"log"
	"net/http"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda" //nolint: gci // This is a false positive
)

// handler is our lambda handler invoked by the `lambda.Start` function call
func handler(ctx context.Context, r events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {

	// Sanity check
	log.Println("Hello World!")

	// Example using another package
	log.Println(configuration.Something())

	// Marshal the request
	j, err := json.Marshal(r)
	if err != nil {
		return events.APIGatewayProxyResponse{Body: "request failed", StatusCode: http.StatusBadRequest}, err
	}

	// Log the request data
	log.Println(string(j))

	// Response
	return events.APIGatewayProxyResponse{Body: "Hello World!", StatusCode: http.StatusOK}, nil
}

// main function to launch the lambda
func main() {
	lambda.Start(handler)
}
