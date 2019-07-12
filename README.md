# Introduction

In this lab, we'll be using the Terraform and ASP.NET MVC code you created in the [previous lab](https://github.com/ecrhoads/InfrastructureAsCode-Lab) to create an automated build/release pipeline. 

## Prereqs

- Azure DevOps account: if you don't have one, go to https://dev.azure.com and create a free account. Use your account from MPN/Visual Studio Subscription.  

- Azure DevOps project: Create a project called DevOpsLab, choose Agile as the process template, and Git as the source control.

- An Azure storage account to hold our Terraform state files. 

    > What is a Terraform state file? Terraform must store state about your managed infrastructure and configuration. This state is used by Terraform to map real world resources to your configuration, keep track of metadata, and to improve performance for large infrastructures.
    >
    > This state is stored by default in a local file named "terraform.tfstate", but it can also be stored remotely, which works better in a team environment.
    >
    > Terraform uses this local state to create plans and make changes to your infrastructure. Prior to any operation, Terraform does a refresh to update the state with the real infrastructure.

    You'll be using an Azure Storage Account to store shared state files for the dev and prod environments.

    Before you go any further, use the Azure portal to create a Resource group named *terraform-state-rg*, and add a storage account named *tfstateXXXX* to the RG (XXXX should be a random 4-digit number, which is used to makes the storage account name unique).

    After creating, create two Private Blob containers: *todo-app-dev-state* and *todo-app-prod-state*, then save the storage account name and key from the *Access Keys* tab of the storage account. We'll be using it later. 

## Module 1: Creating a Build Pipeline for Terraform
In this module, you'll modify the Terraform we created to be more generic, and create a build pipeline that publishes generic Terraform artifacts to Azure DevOps.

### Making Terraform Generic

1. Begin by creating an *iac* and *web* folder in the root of your DevOpsLab git repo. You'll use the iac (stands for infrastructure-as-code) folder to streo the Terraform code, and the web folder to store the ASP.NET source code.

2. Add the Terraform code from the previous lab into the *iac* folder. 

3. Create an *app* folder beneath *iac*, and move the *main.tf* file into the *app* folder.

4. Next, you'll need to modularize (or genericize) the Terraform file. Why? Because we'll be using Terraform file for dev and prod deployments. So, we'll need to be able to substitute all values at deployment time. 

    - Replace the *main.tf* file hard-coded values with variable references. For example:

        ```
        provider "azurerm" {
            tenant_id       = "${var.tenant_id}"
            subscription_id = "${var.subscription_id}"
        }

        module "todo_app" {
            source = "../_modules/cosmos_web_app/"

            application_short_name = "${var.application_short_name}"
            environment = "${var.environment}"
            location = "${var.location}"
        }
        ```

    - Add a backend section to the top of the main.tf file:

        ```
        terraform {
            backend "azurerm" {
                key   = "terraform.tfstate"
            }
        }
        ```

        > The backend config section tells Terraform how and where to store the state file. Here, we're telling it to use the Azure RM provider to store it in a file named *terraform.tfstate*. There's a few pieces missing (like the storage account name, container, and access key), but we'll be supplying that information at run time.

    - Next, create a *vars.tf* file in the *app* folder and declare the variables we just created:

        ```
        variable "tenant_id" {
            description = "Azure tenant where the app will be deployed"
        }

        variable "subscription_id" {
            description = "Azure subscription where the app will be deployed"
        }

        variable "application_short_name" {
            description = "Abbreviated name for the application, used to name associated infrastructure resources"
        }

        variable "environment" {
            description = "The application environment (Dev, Test, QA, Prod)"
        }

        variable "location" {
            description = "The Azure Region where resources will be deployed"
        }
        ```

5. Now that you've added a way to pass variables into our Terraform app, there are various ways of populating these values when you run `terraform apply`. The most popular method is to pass in each variable value as a command line parameter, but this gets exhausting. An alternate way is to create a file named *terraform.tfvars* in the same directory, then add variable values to this file. Let's do that.

    - Add a file named *terraform.tfvars* to the *app* folder

    - Add each variable with a default value to the file:
        ```
        tenant_id = "__tf_tenant_id__"
        subscription_id = "__tf_subscription_id__"
        application_short_name = "__tf_application_short_name__"
        environment = "__tf_environment__"
        location = "__tf_location__"
        ```
        > Woah! I thought we were adding default values...well, we will, but for now, we want to create a template for the values to be added programatically. If you recall the first step in the CICD process is building a genericized artifact that can be used to deploy to multiple environments. Then, at release time, you inject the configuration (or default variable values) immediately before deployment. You may not see it right now, but when we create our release pipeline, we'll use the double underscore syntax to search and replace values.

That's the final Terraform change you'll need to make. Commit your changes and push the commits.

### Creating a Build Pipeline

1. In Azure DevOps, navigate to Pipelines -> Builds.

2. Create a new Build Pipeline. At first, you'll be asked "Where's your code?". On this screen, scroll to the bottom and click the link that reads, **"Use the classic editor to create a pipeline without YAML."**

    > What's the difference between YAML and the classic editor? The classic editor uses a GUI interface to quickly create pipelines. YAML builds give you a coding-like experience. Both system have near-feature-parity. Depending on your background and previous usage of CICD pipeline technologies, you may prefere one over the other. It's up to you, but today you'll be using the classic editor.

3. In the classic editor, select *Azure Repos Git* as your repository and these settings:

    - Team Project: DevOpsLab    
    - Repository: DevOpsLab
    - Branch: master

4. On the *Select a template* screen, clic the *Empty job* link. Now you're ready to create your build pipeline.

    > But, what is a pipeline? A pipeline is (in simple terms) a fancy task runner. Pipelines are organized into a series of 1 or more jobs. Jobs then have a series of tasks that are run in sequence, on after the other. In this exercise, you'll be create a job with several tasks to collect the Terraform source code and publish it as an artifact. Later, we'll use the artifact to deploy to dev and prod environments.

5. Click on *Agent job 1*, rename it to *Build Terraform*.

6. Add and configure a *Copy files* task to stage the Terraform code to be uploaded as an Artifact.

    - Click the *+* sign next to the *Build Terraform* job to add a *Copy files* task.

    - Find the *Copy files* task and add it. You can search for it, or find it under the *Utilities* category.
    
    - Configure it with these values:

        - Display Name: Copy Files to: Staging Directory
        - Source folder: iac
        - Contents: **
        - Target Folder: $(Build.ArtifactStagingDirectory)

            > $(Build.ArtifactStagingDirectory) is a reserved pipeline variable that holds the full path of a special folder on the pipeline server's file system where artifacts shoudl be staged. It's reserved for this specific purpose, so it's safe to copy files we want to upload as artifacts to this location.

7. Add and configure a *Publish build artifacts* task to upload the staging files as an artifact:

    - Find and add the *Publish build artifacts* task.

    - Configure with these values:

        - Display Name: Publish Artifact: terraform
        - Path to Publish: $(Build.ArtifactStagingDirectory)
        - Artifact name: terraform
        - Artifact publish location: Azure Pipelines

            > The artifact name is a special value that we'll use later to reference the collection of files we're uploading as an artifact. 

8. Click the *Save & Queue* button at top to save the pipeline and queue it for execution. After queueing the build, you can monitor it's progress on the screen. Explore the UI by clicking on tasks as they execute - you'll see the command line/terminal output of each command logged and streaming to the screen. 

9. After ~30 seconds, the pipeline should succeed. At the top right, there is an *Artifacts* button. Click it and review the contents of the *terraform* artifact. It should contain the contents of the *iac* source control folder.

That's it! 

## Module 2: Releasing to Dev and Prod

In this module, you'll be using the Terraform build artifact to create a release pipeline that reuses the same code to deploy to dev and prod environments.



## Module 3: Building an ASP.NET MVC App

## Module 4: Updating the Release Pipeline to Deploy Infra & Apps
