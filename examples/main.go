package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"

	ddlambda "github.com/DataDog/datadog-lambda-go"
	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
)

// Response represents the structure of our Lambda response
type Response struct {
	StatusCode int               `json:"statusCode"`
	Headers    map[string]string `json:"headers"`
	Body       string            `json:"body"`
}

// Request represents a simple request structure
type Request struct {
	Name    string `json:"name"`
	Message string `json:"message"`
}

// handleAPIGateway handles API Gateway proxy requests
func handleAPIGateway(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	log.Printf("Received API Gateway request: %s %s", request.HTTPMethod, request.Path)

	// Parse request body if present
	var req Request
	if request.Body != "" {
		if err := json.Unmarshal([]byte(request.Body), &req); err != nil {
			log.Printf("Error parsing request body: %v", err)
			return events.APIGatewayProxyResponse{
				StatusCode: 400,
				Headers: map[string]string{
					"Content-Type": "application/json",
				},
				Body: `{"error": "Invalid request body"}`,
			}, nil
		}
	}

	// Create response
	response := map[string]interface{}{
		"message": "Hello from AWS Lambda with Go!",
		"method":  request.HTTPMethod,
		"path":    request.Path,
	}

	if req.Name != "" {
		response["greeting"] = fmt.Sprintf("Hello, %s!", req.Name)
	}

	if req.Message != "" {
		response["echo"] = req.Message
	}

	responseBody, err := json.Marshal(response)
	if err != nil {
		log.Printf("Error marshaling response: %v", err)
		return events.APIGatewayProxyResponse{
			StatusCode: 500,
			Headers: map[string]string{
				"Content-Type": "application/json",
			},
			Body: `{"error": "Internal server error"}`,
		}, nil
	}

	return events.APIGatewayProxyResponse{
		StatusCode: 200,
		Headers: map[string]string{
			"Content-Type": "application/json",
			"Access-Control-Allow-Origin": "*",
		},
		Body: string(responseBody),
	}, nil
}

// handleSQS handles SQS messages (for worker mode)
func handleSQS(ctx context.Context, sqsEvent events.SQSEvent) error {
	log.Printf("Received SQS event with %d records", len(sqsEvent.Records))

	for _, record := range sqsEvent.Records {
		log.Printf("Processing SQS message: %s", record.MessageId)
		log.Printf("Message body: %s", record.Body)

		// Parse the message body
		var message map[string]interface{}
		if err := json.Unmarshal([]byte(record.Body), &message); err != nil {
			log.Printf("Error parsing SQS message body: %v", err)
			continue
		}

		// Process the message (add your business logic here)
		log.Printf("Processing message: %+v", message)

		// Simulate some work
		// In a real application, you would process the message here
		// For example: save to database, call external API, etc.
	}

	return nil
}

// handleGeneric handles any other type of event
func handleGeneric(ctx context.Context, event json.RawMessage) (interface{}, error) {
	log.Printf("Received generic event: %s", string(event))

	response := map[string]interface{}{
		"message": "Hello from AWS Lambda with Go!",
		"event":   string(event),
	}

	return response, nil
}

// router determines which handler to use based on the event type
func router(ctx context.Context, event json.RawMessage) (interface{}, error) {
	// Try to determine the event type
	var eventMap map[string]interface{}
	if err := json.Unmarshal(event, &eventMap); err != nil {
		log.Printf("Error parsing event: %v", err)
		return handleGeneric(ctx, event)
	}

	// Check if it's an API Gateway event
	if _, hasRequestContext := eventMap["requestContext"]; hasRequestContext {
		var apiEvent events.APIGatewayProxyRequest
		if err := json.Unmarshal(event, &apiEvent); err != nil {
			log.Printf("Error parsing API Gateway event: %v", err)
			return handleGeneric(ctx, event)
		}
		return handleAPIGateway(ctx, apiEvent)
	}

	// Check if it's an SQS event
	if records, hasRecords := eventMap["Records"]; hasRecords {
		if recordsArray, ok := records.([]interface{}); ok && len(recordsArray) > 0 {
			if firstRecord, ok := recordsArray[0].(map[string]interface{}); ok {
				if _, hasSQS := firstRecord["eventSource"]; hasSQS {
					var sqsEvent events.SQSEvent
					if err := json.Unmarshal(event, &sqsEvent); err != nil {
						log.Printf("Error parsing SQS event: %v", err)
						return handleGeneric(ctx, event)
					}
					return nil, handleSQS(ctx, sqsEvent)
				}
			}
		}
	}

	// Default to generic handler
	return handleGeneric(ctx, event)
}

func main() {
	// Check if Datadog is enabled via environment variable
	// When dd-tracing is enabled, DD_API_KEY_SECRET_ARN will be set
	if os.Getenv("DD_API_KEY_SECRET_ARN") != "" {
		log.Println("Datadog tracing enabled - wrapping Lambda handler")
		lambda.Start(ddlambda.WrapFunction(router, nil))
	} else {
		log.Println("Datadog tracing disabled - using standard Lambda handler")
		lambda.Start(router)
	}
} 