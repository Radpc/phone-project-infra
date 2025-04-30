# Device project - Infra

## Description
This project was made using `Terraform`, for building the cloud environment for the other applications of the project.

## Architecture
![image](https://github.com/user-attachments/assets/501befc4-5444-4177-8ab5-f8e88a3010c8)
* The API port is public for accessing the docs if needed! But could easily be private inside the subnet.

## Deploy
On the `main` branch, with every push the workflow runs, applying the current terraform configurations to AWS.

## Keypoints
- **Scalable**: Instances have a `count` parameter and variables are parametrized by environment input.
- **Safe**: Sensitive data is passed through using `github secrets`
- Because the `terraform apply` is made on a `github action` (temporary files), the state is saved using an EC2 instance (see `Backend` file)

## Note
The ec2 model used was a t2.medium (instead of the t2.micro). It was having issues with `npm install` and often running out of memory.
