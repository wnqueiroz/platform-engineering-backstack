package main

import (
	"context"
	"flag"
	"fmt"
	"os"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

func getKubeConfig() (*rest.Config, error) {
	kubeconfig := flag.String("kubeconfig", os.Getenv("HOME")+"/.kube/config", "path to kubeconfig")
	flag.Parse()

	config, err := rest.InClusterConfig()
	if err != nil {
		config, err = clientcmd.BuildConfigFromFlags("", *kubeconfig)
		if err != nil {
			return nil, fmt.Errorf("failed to load kubeconfig: %v", err)
		}
	}
	return config, nil
}

func main() {
	config, err := getKubeConfig()
	if err != nil {
		fmt.Printf("Error retrieving Kubernetes configuration: %v\n", err)
		return
	}

	dynClient, err := client.New(config, client.Options{})
	if err != nil {
		fmt.Printf("Error creating dynamic client: %v\n", err)
		return
	}

	claim := &unstructured.Unstructured{
		Object: map[string]any{
			"apiVersion": "hooli.tech/v1alpha1",
			"kind":       "NoSQLClaim",
			"metadata": map[string]any{
				"name":      "my-nosql-database",
				"namespace": "default",
			},
			"spec": map[string]any{
				"location": "US",
			},
		},
	}

	err = dynClient.Create(context.TODO(), claim)
	if err != nil {
		fmt.Printf("Error creating Claim: %v\n", err)
		return
	}

	fmt.Println("Claim successfully created!")
}
