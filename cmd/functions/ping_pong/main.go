// Package main is the entry point for the ping_pong lambda function
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
func handler(_ context.Context, r events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {

	// Sanity check
	log.Println("Ping Pong!")

	// Example using another package
	log.Println(configuration.Something())

	// Start a segment for X-Ray
	// var seg *xray.Segment
	// ctx, seg = xray.BeginSegment(ctx, "marshall-print")

	// Marshal the request
	j, err := json.Marshal(r)
	if err != nil {
		return events.APIGatewayProxyResponse{Body: "request failed", StatusCode: http.StatusBadRequest}, err
	}

	// Log the request data
	log.Println(string(j))

	// Close the segment for X-Ray
	// seg.Close(nil)

	// Response
	return events.APIGatewayProxyResponse{Body: "Ping Pong!", StatusCode: http.StatusOK}, nil
}

// main function to launch the lambda
func main() {
	lambda.Start(handler)
}
