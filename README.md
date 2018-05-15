PLEASE READ BEFORE PROCEEDING!

This script supports staging HPOC clusters for [Nutanix Workshops](http://www.nutanixworkshops.com).

## Available Workshops ##

1. Calm Introduction Workshop (AOS/AHV 5.6)
2. Citrix Desktop on AHV Workshop (AOS/AHV 5.6)

## HPOC Cluster Reservation ##

Make your new https://rx.corp.nutanix.com:8443/ reservation with:

- __Region:__ NX-US-West region only
- __AOS + Hypevisor:__ proper versions for your workshop, specified above
  - Older or newer versions may not function as expected
- __OS Images:__ *do not* add addition images (CentOS, Windows2012, etc.) to your reservation

## Staging Your HPOC ##

All clusters must be Foundationed prior to Workshop staging.

This script should be run from a host on the corporate/lab network,
 such as a CentOS VM running on an HPOC cluster or your laptop with VPN access.
Execute the following:

    git clone https://github.com/nutanixworkshops/stageworkshop.git
    cd stageworkshop
    chmod +x stage_workshop.sh

Next, you'll need to create or reuse and update a text file (*e.g.:* example_pocs.txt)
 containing your cluster IP and password details.
 It's easiest to create this file in the same directory as the stage_workshop.sh script.
 Input files must use the following format:

    <Nutanix Cluster #1 IP>|<Cluster #1 Password>
    <Nutanix Cluster #2 IP>|<Cluster #2 Password>
    ...
    <Nutanix Cluster #N IP>|<Cluster #N Password>

For example:

    10.21.1.37|nx2Tech123!
    10.21.7.37|nx2Tech517!
    #10.21.5.37|nx2Tech789! <-- The script will ignore commented out clusters
    10.21.55.37|nx2Tech456!

Finally, execute the script to stage the HPOC clusters defined in your text file.

### Interactive Usage ###

````./stage_workshop.sh````

Running the script interactively
 will prompt you to input the name of your text file containing your cluster IP and password details.
 You will then be prompted to choose a Workshop to stage.

### Non-interactive Usage ###

````./stage_workshop.sh -f example_pocs.txt -w workshop_number````

Each staging option will deploy:

- all images required to complete a given workshop
- a domain controller (ntnxlab.local)
- Prism Central
- configuring AHV networks for your Primary and Secondary VLANs.

After staging (~30m), you can re-run the stage_workshop script and select "Validate Staged Clusters" to perform a quick check to ensure all images were uploaded and that Prism Central was provisioned as expected.

If you encounter issues reach out to @matt on Slack.
