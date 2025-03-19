# Using the Salesforce CLI

1. Download and install the Salesforce Command Line Interface (CLI) using the instructions here: https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_install_cli.htm
2. Download the files in this repository, which contains the components used for RFQ.
   - From the browser, click the "<> Code" dropdown for download options.
   - Alternatively, you can use the "git clone" command to download the files. For more information, see: https://docs.github.com/en/repositories/creating-and-managing-repositories/cloning-a-repository
3. If the repository was downloaded as a .zip file, extract the files
   - On Windows, right click and select "*Extract All...*". Follow the prompts that appear on screen.
   - On Mac, double click the file and its contents will be extracted automatically in the same location.
4. If it's not already running, launch the program *Terminal* (on Mac or Linux) or *Powershell* (on Windows).
5. Use the change directory (cd) command to navigate to the unzipped directory. For example, if the files were extracted in the *Downloads* folder, type and enter the command "cd Downloads/cpq-rfq-v2".
6. Type and enter the command "ls" and a list of files and folders in that directory will be returned. Included in the list should be the folder "*src*" and the file "*sfdx-project.json*", along with this README.
7. Run the command "sf auth web login --alias *myOrg* --instance-url *https://example-dev-ed.my.salesforce.com*"
   - Replace the URL following "--instance-url " with your Salesforce org URL.
   - The text following "--alias " is a nickname that is used to identify and reference the correct Salesforce org (multiple Salesforce orgs can be connected to a single machine). The example "myOrg" will be used for the purposes of this guide; if using another alias here, be sure to use that same alias in the following steps.
8. The URL specified in the previous login command will be opened in the default browser. Log in and authorize the "Salesforce CLI" connected app.
9. In the command line, run the command "sf project deploy start --source-dir src --target-org myOrg". After a few moments, the command line will return a confirmation message, "Deploy Succeeded."
10. (Optional) If the Salesforce org isn’t already open in a browser, it can be opened and logged in by running the command “sf org open --target-org myOrg”.