package main

import (
	"context"
	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"log"
)

// Request is the request type
type Request = events.APIGatewayProxyRequest

// Response is the response type
type Response = events.APIGatewayProxyResponse

// setting up the services
//var config = configuration.New()
//var store = database.NewUserStore(config)
//var service = service.NewUserService(store)

func handler(ctx context.Context, r Request) (Response, error) {

	log.Println("Hello World!")

	// Response
	return events.APIGatewayProxyResponse{Body: "Hello World!", StatusCode: 200}, nil
}

func main() {
	lambda.Start(handler)
}
