# HPoC Automation: Push Button Calm

## Prerequisites ##
1. Tested on Mac, probably works on Linux.
2. Open a terminal: install git, jq, and sshpass.

### Acknowledgements ###

The entire Global Technical Sales Enablement team has delivered an amazing amount of content and automation for Nutanix TechSummits and Workshops. Along with the Corporate SE team automation gurus, it has been a pleasure to work with all of them and this work stands on the shoulder of those giants. Thank you!

## Procedure ##

0. Crank some tunes!
1. Browse to: https://github.com/mlavi/stageworkshop
   1. I will submit a pull request shortly to merge my work.
2. In a terminal:

        git clone https://github.com/mlavi/stageworkshop.git
3. Review our HPoC reservation details
   1. Choose the PE URL to show unavailable during foundation process.
   2. Update octet and password in ````example_pocs.txt```` and save.
4. Side by side:
   1. Browser = RX automation: cluster foundation status
   2. Terminal = cut and paste from example_pocs.txt:

          ./stage_workshop.sh -f example_pocs.txt -w 1 #calm

        1. In the terminal, copy and paste the command to monitor the ````stage_calmhow.sh```` progress on a CVM.
