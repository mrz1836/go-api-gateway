package main

import (
	"context"
	"encoding/json"
	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"go-api-gateway/configuration"
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

	log.Println(configuration.Something())

	j, err := json.Marshal(r)
	if err != nil {
		return events.APIGatewayProxyResponse{Body: "Request failed", StatusCode: 400}, err
	}

	log.Println(string(j))

	// Response
	return events.APIGatewayProxyResponse{Body: "Hello World!", StatusCode: 200}, nil
}

func main() {
	lambda.Start(handler)
}
