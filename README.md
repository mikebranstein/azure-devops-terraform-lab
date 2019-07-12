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

1. Navigate to the Pipelines -> Releases area, then create a new release pipeline.

2. Click the *Empty Job* template button to create an empty pipeline.

3. Change the name of *Stage 1* to *Dev*.

4. Click the *+ Add* button next to *Artifacts* to add an artifact. Configure it:

    - Source type: Build
    - Project: DevOpsLab
    - Source (build pipeline): DevOpsLab-CI
    - Default version: latest
    - Source alias: _DevOpsLab-CI

5. Click the *1 job, 0 task* link under the *Dev* Stage to begin adding jobs and tasks to the release pipeline.

    > Release pipelines are like build pipelines, as they have Jobs and Tasks. But, they introduce another component: stages. For now, you can think of stages as a concept akin to an environment - so each environment you deploy to will have a stage: dev stage and prod stage. 
    >
    > Stages also come with automation and approvals, so it's possible to automatically start a stage when a new artifact is available (or when a build completes) or when another stage completes (for example, starting a prod stage deployment when the dev stage completes). You can also gate a stage execution with a robust approval chain.   
    >
    > Having a single stage per environment makes a lot of sense, but in more complex environments multi-stage-per-environment releases may be adventageous. But in general, we typically start with a stage per environment.

6. Click on *Agent Job* and rename it to *Deploy Infrastructure*. 

7. Add a *Replace Tokens* task to the job.

    > Before you can add this task, you'll need to install and authorize an Azure DevOps extension from the Marketplace. The extension is called *Colin's ALM Corner Build & Release Tools*. 
    >
    > You can search for the extension from the Marketplace tab in the add task area. Follow the on-screen prompts to install and authorize this task for your Azure DevOps account. Then return to the *Add Task* screen and press the built-in *Refresh* link next to *Add tasks* to refresh the list of available tasks.

    - Add the *Replace Tokens* task and configure with these values:

        - Display name: Replace tokens in terraform-tfvars
        - Source path: $(System.DefaultWorkingDirectory)/_DevOpsLab-CI/terraform/app
        - Target File Pattern: terraform.tfvars

    - Save the pipeline.

    > What does Replace Tokens do? You'll recall that we created the terraform.tfvars file with placeholder/template values surrounded by double underscores. This task searches a file for that specific pattern (or token) and replaces it with a value we configure in the variables section of the pipeline. The simplicity of the task lies in the naming of your tokens and variables. If the token is named _ _ DatabaseName _ _, the task searches for a variable named *DatabaseName* and substitutes the value automatically. Easy peasy.

8. Now that you know how the Replace tokens task works, navigate to the pipeline variables tab and add variables for the 5 values in the teerraform.tfvars file.

    - Name: tf_application_short_name, Value: todo, Scope: Dev
    - Name: tf_environment, Value: dev, Scope: Dev
    - Name: tf_location, Value: east us 2, Scope: Dev
    - Name: tf_subscription_id: Value: your azure sub id, Scope: Dev
    - Name: tf_tenant_id: Value: your Azure tenant id for the sub, Scope: Dev

        > You may have noticed the Scope value we set to *Dev* above. Scope refers to which Stage a variable applies. You can select a specific stage (like Dev), or *Release*, which applies the variable to all stages (the entire release pipeline).

9. Return to the Dev stage job and tasks. Search the Marketplace for another task named Terraform, created by Peter Groenewegen. Install and approve it. 

10. Add the *Run Terraform* task to pipeline and configure it:

    - Display name: TF plan
    - Terraform template path: $(System.DefaultWorkingDirectory)/_DevOpsLab-CI/terraform/app 
    - Terraform arguments: plan
    - Check the *Install Terraform* box
    - Terraform version: latest
    - Azure Connection Type: Azure Resource Manager
    - Azure Subscription: select yours
    - Init State in Azure Storage: checked
    - Specify Storage Account: checked
    - Resource Group: terraform-state-rg
    - Storage Account: tfstateXXXX, (remember this from above)
    - Container Name: todo-app-dev-state, (b/c this is the Dev stage pipeline)

11. Add a second *Run Terraform* task to pipeline and configure it:

    - Display name: TF apply
    - Terraform template path: $(System.DefaultWorkingDirectory)/_DevOpsLab-CI/terraform/app 
    - Terraform arguments: apply -auto-approve
    - Check the *Install Terraform* box
    - Terraform version: latest
    - Azure Connection Type: Azure Resource Manager
    - Azure Subscription: select yours
    - Init State in Azure Storage: checked
    - Specify Storage Account: checked
    - Resource Group: terraform-state-rg
    - Storage Account: tfstateXXXX, (remember this from above)
    - Container Name: todo-app-dev-state, (b/c this is the Dev stage pipeline) 

12. Save the pipeline.

13. Queue the pipeline and deploy to the Dev stage. Just as you did with the build, you can monitor the pipeline. Ensure it succeeds (it may take ~5-7 minutes). 

14. Validate it created the resources you were expecting.

15. Clone the Dev stage of the pipeline to create a Prod stage.

16. Adjust these setting in the Prod stage tasks and variables:

    - Duplicate all variables, changing the values as needed so they reflect "prod" environment values (specifically tf_environment and the Scope of all variables)

    - For the TF plan and TF apply steps, ensure the storage account container name is set to *todo-app-prod-state*

17. Save and queue the pipeline again. Validate it updates the dev environment and creates a prod environment.

Congrats! You just created an infra-as-code CICD pipeline. 

## Module 3: Building an ASP.NET MVC App

In this module, you'll add the ToDo app to source control, update the build pipeline, and learn how to use the parameters.xml file to parameterize configuration files.

### Source Controlling the ToDo App

1. Using VS Code, add a *.gitignore* file to the *web* folder. *.gitignore* files tell the git source control engine which files to ignore when adding files/folders to source control. Visual Studio projects create a lot of files that don't need saved in source control (i.e., compiled code, NuGet packages, etc.).

    - Place the following inside your *.gitignore* file:

        ```
        ## Ignore Visual Studio temporary files, build results, and
        ## files generated by popular Visual Studio add-ons.
        ##
        ## Get latest from https://github.com/github/gitignore/blob/master/VisualStudio.gitignore

        # User-specific files
        *.rsuser
        *.suo
        *.user
        *.userosscache
        *.sln.docstates

        # User-specific files (MonoDevelop/Xamarin Studio)
        *.userprefs

        # Mono auto generated files
        mono_crash.*

        # Build results
        [Dd]ebug/
        [Dd]ebugPublic/
        [Rr]elease/
        [Rr]eleases/
        x64/
        x86/
        [Aa][Rr][Mm]/
        [Aa][Rr][Mm]64/
        bld/
        [Bb]in/
        [Oo]bj/
        [Ll]og/

        # Visual Studio 2015/2017 cache/options directory
        .vs/
        # Uncomment if you have tasks that create the project's static files in wwwroot
        #wwwroot/

        # Visual Studio 2017 auto generated files
        Generated\ Files/

        # MSTest test Results
        [Tt]est[Rr]esult*/
        [Bb]uild[Ll]og.*

        # NUnit
        *.VisualState.xml
        TestResult.xml
        nunit-*.xml

        # Build Results of an ATL Project
        [Dd]ebugPS/
        [Rr]eleasePS/
        dlldata.c

        # Benchmark Results
        BenchmarkDotNet.Artifacts/

        # .NET Core
        project.lock.json
        project.fragment.lock.json
        artifacts/

        # StyleCop
        StyleCopReport.xml

        # Files built by Visual Studio
        *_i.c
        *_p.c
        *_h.h
        *.ilk
        *.meta
        *.obj
        *.iobj
        *.pch
        *.pdb
        *.ipdb
        *.pgc
        *.pgd
        *.rsp
        *.sbr
        *.tlb
        *.tli
        *.tlh
        *.tmp
        *.tmp_proj
        *_wpftmp.csproj
        *.log
        *.vspscc
        *.vssscc
        .builds
        *.pidb
        *.svclog
        *.scc

        # Chutzpah Test files
        _Chutzpah*

        # Visual C++ cache files
        ipch/
        *.aps
        *.ncb
        *.opendb
        *.opensdf
        *.sdf
        *.cachefile
        *.VC.db
        *.VC.VC.opendb

        # Visual Studio profiler
        *.psess
        *.vsp
        *.vspx
        *.sap

        # Visual Studio Trace Files
        *.e2e

        # TFS 2012 Local Workspace
        $tf/

        # Guidance Automation Toolkit
        *.gpState

        # ReSharper is a .NET coding add-in
        _ReSharper*/
        *.[Rr]e[Ss]harper
        *.DotSettings.user

        # JustCode is a .NET coding add-in
        .JustCode

        # TeamCity is a build add-in
        _TeamCity*

        # DotCover is a Code Coverage Tool
        *.dotCover

        # AxoCover is a Code Coverage Tool
        .axoCover/*
        !.axoCover/settings.json

        # Visual Studio code coverage results
        *.coverage
        *.coveragexml

        # NCrunch
        _NCrunch_*
        .*crunch*.local.xml
        nCrunchTemp_*

        # MightyMoose
        *.mm.*
        AutoTest.Net/

        # Web workbench (sass)
        .sass-cache/

        # Installshield output folder
        [Ee]xpress/

        # DocProject is a documentation generator add-in
        DocProject/buildhelp/
        DocProject/Help/*.HxT
        DocProject/Help/*.HxC
        DocProject/Help/*.hhc
        DocProject/Help/*.hhk
        DocProject/Help/*.hhp
        DocProject/Help/Html2
        DocProject/Help/html

        # Click-Once directory
        publish/

        # Publish Web Output
        *.[Pp]ublish.xml
        *.azurePubxml
        # Note: Comment the next line if you want to checkin your web deploy settings,
        # but database connection strings (with potential passwords) will be unencrypted
        *.pubxml
        *.publishproj

        # Microsoft Azure Web App publish settings. Comment the next line if you want to
        # checkin your Azure Web App publish settings, but sensitive information contained
        # in these scripts will be unencrypted
        PublishScripts/

        # NuGet Packages
        *.nupkg
        # NuGet Symbol Packages
        *.snupkg
        # The packages folder can be ignored because of Package Restore
        **/[Pp]ackages/*
        # except build/, which is used as an MSBuild target.
        !**/[Pp]ackages/build/
        # Uncomment if necessary however generally it will be regenerated when needed
        #!**/[Pp]ackages/repositories.config
        # NuGet v3's project.json files produces more ignorable files
        *.nuget.props
        *.nuget.targets

        # Microsoft Azure Build Output
        csx/
        *.build.csdef

        # Microsoft Azure Emulator
        ecf/
        rcf/

        # Windows Store app package directories and files
        AppPackages/
        BundleArtifacts/
        Package.StoreAssociation.xml
        _pkginfo.txt
        *.appx
        *.appxbundle
        *.appxupload

        # Visual Studio cache files
        # files ending in .cache can be ignored
        *.[Cc]ache
        # but keep track of directories ending in .cache
        !?*.[Cc]ache/

        # Others
        ClientBin/
        ~$*
        *~
        *.dbmdl
        *.dbproj.schemaview
        *.jfm
        *.pfx
        *.publishsettings
        orleans.codegen.cs

        # Including strong name files can present a security risk
        # (https://github.com/github/gitignore/pull/2483#issue-259490424)
        #*.snk

        # Since there are multiple workflows, uncomment next line to ignore bower_components
        # (https://github.com/github/gitignore/pull/1529#issuecomment-104372622)
        #bower_components/

        # RIA/Silverlight projects
        Generated_Code/

        # Backup & report files from converting an old project file
        # to a newer Visual Studio version. Backup files are not needed,
        # because we have git ;-)
        _UpgradeReport_Files/
        Backup*/
        UpgradeLog*.XML
        UpgradeLog*.htm
        ServiceFabricBackup/
        *.rptproj.bak

        # SQL Server files
        *.mdf
        *.ldf
        *.ndf

        # Business Intelligence projects
        *.rdl.data
        *.bim.layout
        *.bim_*.settings
        *.rptproj.rsuser
        *- [Bb]ackup.rdl
        *- [Bb]ackup ([0-9]).rdl
        *- [Bb]ackup ([0-9][0-9]).rdl

        # Microsoft Fakes
        FakesAssemblies/

        # GhostDoc plugin setting file
        *.GhostDoc.xml

        # Node.js Tools for Visual Studio
        .ntvs_analysis.dat
        node_modules/

        # Visual Studio 6 build log
        *.plg

        # Visual Studio 6 workspace options file
        *.opt

        # Visual Studio 6 auto-generated workspace file (contains which files were open etc.)
        *.vbw

        # Visual Studio LightSwitch build output
        **/*.HTMLClient/GeneratedArtifacts
        **/*.DesktopClient/GeneratedArtifacts
        **/*.DesktopClient/ModelManifest.xml
        **/*.Server/GeneratedArtifacts
        **/*.Server/ModelManifest.xml
        _Pvt_Extensions

        # Paket dependency manager
        .paket/paket.exe
        paket-files/

        # FAKE - F# Make
        .fake/

        # CodeRush personal settings
        .cr/personal

        # Python Tools for Visual Studio (PTVS)
        __pycache__/
        *.pyc

        # Cake - Uncomment if you are using it
        # tools/**
        # !tools/packages.config

        # Tabs Studio
        *.tss

        # Telerik's JustMock configuration file
        *.jmconfig

        # BizTalk build output
        *.btp.cs
        *.btm.cs
        *.odx.cs
        *.xsd.cs

        # OpenCover UI analysis results
        OpenCover/

        # Azure Stream Analytics local run output
        ASALocalRun/

        # MSBuild Binary and Structured Log
        *.binlog

        # NVidia Nsight GPU debugger configuration file
        *.nvuser

        # MFractors (Xamarin productivity tool) working folder
        .mfractor/

        # Local History for Visual Studio
        .localhistory/

        # BeatPulse healthcheck temp database
        healthchecksdb

        # Backup folder for Package Reference Convert tool in Visual Studio 2017
        MigrationBackup/
        ```

2. Move your ToDo app into the *web* folder.

3. Back in Visual Studio, add a file to the ToDo web app project named *parameters.xml*. Note that you need to use Visual Studio to add the file, so it is registered to be a file included in the project, not just a random file. 

4. Add XML configuration to tell MSBuild that the Cosmos Db Endpoint and Key should be parameterized.

    > What is MSBuild? The Microsoft Build Engine is a platform for building applications. This engine, which is also known as MSBuild, provides an XML schema for a project file that controls how the build platform processes and builds software. Visual Studio uses MSBuild, but it doesn't depend on Visual Studio.
    >
    > In a later step, you'll be using MSBuild to build something called a WebDeploy package. WebDeploy is a technology that allows you to deploy ASP.NET web apps to IIS web servers.

    - Insert XML into the file:

        ```
        <parameters>
            <parameter name="CosmosDbEndpoint" defaultValue="__CosmosDbEndpoint__">
                <parameterEntry
                kind="XmlFile"
                scope="obj\\Release\\Package\\PackageTmp\\Web\.config$"
                match="/configuration/appSettings/add[@key='endpoint']/@value" />
            </parameter>

            <parameter name="CosmosDbAuthKey" defaultValue="__CosmosDbAuthKey__">
                <parameterEntry
                kind="XmlFile"
                scope="obj\\Release\\Package\\PackageTmp\\Web\.config$"
                match="/configuration/appSettings/add[@key='authKey']/@value" />
            </parameter>
        </parameters>
        ```

        > Wow, That's a whole lot to understand at once - let's decompose it. First, you'll notice that we have 2 parameters: one for the endpoint configuration setting and one for the authKey setting. These are the 2 values we want to update. So each parameter XML fragment instructs MSBuild and WebDeploy how to change these values when deployed.
        >
        > Each parameter XML fragment has 3 components: the *name*, *defaultValue*, and the *parameterEntry*. 
        >
        > The name is simply a unique name to track each parameter. It does not need to match your confguration parameter - it just needs to be unique.
        >
        > DefaultValue is the value we will be substituting at deployment time. You'll notice it is another double underscore value, so we'll be using the same technique you learned earlier with the *Replace Tokens* task.
        >
        > ParameterEntry tells WebDeploy where to look for the value that will be replaced. The scope attribute points to the file location, and the match attriute uses an XPath notation to search within the scoped file to perform the replacement. It's ok if you're scratching your head on the scope attribute - the path is a bit misleading, but will make sense to WebDeploy.

5. Commit your changes and push the commits. 

### Updating the Build Pipeline

1. Return to your build pipeline in Azure DevOps and edit it.

2. Add a new Job to the pipeline. Name it *Build Web*.

3. Add a *NuGet* task to the job. Configure it with the following parameters:

    - Display name: NuGet restore
    - Command: restore
    - Path to solution: web/todo.sln
    - Feeds to use: *Feeds I have selected here*
    - Check *Use packages from NuGet.org*

        > This task instructs the pipeline to inspect the todo solution for any NuGet packages, and download them on to the build server. NuGet is a system that manages software dependencies for .NET projects and is the way Microsoft deploys updates. 
        >
        > Previously, you had added the DocumentDb NuGet package to your app - this lets you access code that was writtein to interact with CosmosDb.
        >
        > When you tested your website, Visual Studio automatically restored your NuGet packages, but we didn't save them in source control (b/c they're big and it's trivial to download them).

4. Add a *Visual Studio build* task to the job. Configure it with these values:

    - Display name: Build solution web/todo.sln
    - Solution: web/todo.sln
    - Visual Studio Version: latest
    - MSBuild arguments; /p:DeployOnBuild=true /p:WebPublishMethod=Package  /p:PackageAsSingleFile=true /p:SkipInvalidConfigurations=true /p:PackageLocation="$(Build.ArtifactStagingDirectory)"
    - Platform: any cpu
    - Configuration: release
    - Check *Clean*

        > **Holy Build Parameters Batman!**
        >
        > Yeah, that's a lot, but these parameters are what tell MSBuild to create a WebDeploy package after building our website. Of special note is the *PackageLocation* parameter, that places the WebDeploy package in the special artifact staging directory - you'll remember this from earlier in the lab.

5. Add a *Publish build artifacts* task to the job and configure it:

    - Display name: Publish Artifact: web
    - Path to publish: $(Build.ArtifactStagingDirectory)
    - Artifact name: web
    - Artifact Publish Location: Azure Pipelines

6. Save and queue your build. Monitor the logs and ensure you have a web artifact that is produced from the build. Inspect the web artifact and you'll see it has 5 files inside:

    - todo.deploy-readme.txt: a readme file for how to deploy this package
    - todo.deploy.cmd: a deployment script used by WebDeploy to deploy to IIS
    - todo.SetParameters.xml: a transformed version of our parameters.xml file, with the double underscore parameters - this is the file we'll be replacing the tokens in
    - todo.SourceManifest.xml: file describing the contents of our deploy package
    - todo.zip: our compiled website, in a zip file

        > If you unzip the compiled website, you'll see there is a  super long directory structure. When I said WebDeploy uses an obscure directory structure, this si what I was referring to. If you're really interested try to find the web.config file and compare it's path to the scope attribute from the parameters.xml file. 

That's it! You've created a genericized build of an ASP.NET website. Next step use the artifact to deploy it to our newly-created Azure infrastructure.

## Module 4: Updating the Release Pipeline to Deploy Infra & Apps

In this final module, you'll be updating the Dev and Prod release stages by adding a job and tasks to deploy the web artifact to the Azure environments created by your Terraform deployment. Hop to it.

1. 
