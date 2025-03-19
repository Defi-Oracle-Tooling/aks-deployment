# Project Documentation

## Overview
This project deploys a **Hyperledger Besu** blockchain network using **Azure Kubernetes Service (AKS)**. The deployment process is automated and includes state management, logging, error handling, and notifications.

## Table of Contents
1. [Deployment Process](deployment_process.md)
2. [How This Works](how_this_works.md)
3. [Handling Deployment Failures](handling_deployment_failures.md)
4. [Quota Overview](quota_overview.md)
5. [Deployment Script](deployment_script.md)
6. [Usage](usage.md)
7. [Files](files.md)
8. [Prerequisites](prerequisites.md)
9. [Notes](notes.md)

## Deployment Process
The deployment process involves cloning the repository, ensuring Azure CLI is installed and logged in, and running the deployment script. Detailed steps are provided in the [Deployment Process](deployment_process.md) document.

## How This Works
The deployment script reads the `regions.txt` file for all supported Azure regions, fetches available vCPU quotas dynamically, chooses the best VM size, and automatically scales nodes based on quotas. Detailed information is provided in the [How This Works](how_this_works.md) document.

## Handling Deployment Failures
The script logs errors in `failed_regions.log`, triggers alerts via Azure Monitor if deployments fail, and cleans up partially created resources. Detailed information is provided in the [Handling Deployment Failures](handling_deployment_failures.md) document.

## Quota Overview
The quota overview provides information on the maximum vCPUs and optimal VM sizes for different regions. Detailed information is provided in the [Quota Overview](quota_overview.md) document.

## Deployment Script
The deployment script deploys Azure Kubernetes Service (AKS) clusters to multiple regions as specified in `regions.txt`. Detailed information is provided in the [Deployment Script](deployment_script.md) document.

## Usage
The usage document provides instructions on how to run the deployment script and review the log files. Detailed information is provided in the [Usage](usage.md) document.

## Files
The files document provides information on the various files used in the project, including `regions.txt`, `success_regions.log`, `failed_regions.log`, and `deployment.log`. Detailed information is provided in the [Files](files.md) document.

## Prerequisites
The prerequisites document provides information on the necessary tools and permissions required to run the deployment script. Detailed information is provided in the [Prerequisites](prerequisites.md) document.

## Notes
The notes document provides additional information and tips for running the deployment script. Detailed information is provided in the [Notes](notes.md) document.
