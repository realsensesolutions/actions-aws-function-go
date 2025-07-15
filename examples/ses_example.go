package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ses"
	"github.com/aws/aws-sdk-go-v2/service/ses/types"
)

type EmailRequest struct {
	To      string `json:"to"`
	Subject string `json:"subject"`
	Body    string `json:"body"`
}

type EmailResponse struct {
	StatusCode int    `json:"statusCode"`
	MessageID  string `json:"messageId,omitempty"`
	Error      string `json:"error,omitempty"`
}

func sendEmail(ctx context.Context, req EmailRequest) (*EmailResponse, error) {
	// Load AWS configuration
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		log.Printf("Error loading AWS config: %v", err)
		return &EmailResponse{
			StatusCode: 500,
			Error:      "Failed to load AWS configuration",
		}, nil
	}

	// Create SES client
	sesClient := ses.NewFromConfig(cfg)

	// Build email
	input := &ses.SendEmailInput{
		Source: aws.String("noreply@yourdomain.com"), // Must be verified in SES
		Destination: &types.Destination{
			ToAddresses: []string{req.To},
		},
		Message: &types.Message{
			Subject: &types.Content{
				Data: aws.String(req.Subject),
			},
			Body: &types.Body{
				Text: &types.Content{
					Data: aws.String(req.Body),
				},
			},
		},
	}

	// Send email
	output, err := sesClient.SendEmail(ctx, input)
	if err != nil {
		log.Printf("Error sending email: %v", err)
		return &EmailResponse{
			StatusCode: 500,
			Error:      fmt.Sprintf("Failed to send email: %v", err),
		}, nil
	}

	return &EmailResponse{
		StatusCode: 200,
		MessageID:  *output.MessageId,
	}, nil
}

func handleRequest(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	var emailReq EmailRequest
	if err := json.Unmarshal([]byte(request.Body), &emailReq); err != nil {
		return events.APIGatewayProxyResponse{
			StatusCode: 400,
			Headers:    map[string]string{"Content-Type": "application/json"},
			Body:       `{"error": "Invalid request body"}`,
		}, nil
	}

	// Send email
	response, err := sendEmail(ctx, emailReq)
	if err != nil {
		return events.APIGatewayProxyResponse{
			StatusCode: 500,
			Headers:    map[string]string{"Content-Type": "application/json"},
			Body:       `{"error": "Internal server error"}`,
		}, nil
	}

	responseBody, _ := json.Marshal(response)
	return events.APIGatewayProxyResponse{
		StatusCode: response.StatusCode,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       string(responseBody),
	}, nil
}

func main() {
	lambda.Start(handleRequest)
}
