# HPoC Automation: Push Button Calm

## Prerequisites ##
1. Tested on Mac, probably works on Linux.
2. A terminal, command line: git, jq, and sshpass.

### Acknowledgements ###

The entire Global Technical Sales Enablement team has delivered an amazing amount of content and automation for Nutanix TechSummits and Workshops. Along with the Corporate SE team automation gurus, it has been a pleasure to work with all of them and this work stands on the shoulder of those giants. Thank you!

## Procedure ##

0. Crank some tunes!
1. *Browse* to: https://github.com/mlavi/stageworkshop
   - I will submit a pull request shortly to merge my work.
1. *Launch a new terminal*: Change font size for demo, create/change to a new directory.

        git clone https://github.com/mlavi/stageworkshop.git ; tree
1. Review HPoC reservation details in rx:
   0. __Browser:__ Highlight the HPoC #, commit that to memory: it is used for octet update. Copy the PE admin password.
   0. __Terminal:__ Update the *octet* and *password* in ````example_pocs.txt```` and save.
      - *OPTIONAL:* Make a mistake with the octet to show a failure mode.
   0. __Browser:__ Choose the PE URL to show unavailable during foundation process.
1. Side by side: (screens because split desktop doesn't work well enough)
   1. __Browser:__ RX automation: cluster foundation status
   2. __Terminal:__ cut and paste from example_pocs.txt:

          ./stage_workshop.sh -f example_pocs.txt -w 1 #calm

        1. In the terminal, copy and paste the command to monitor the ````stage_calmhow.sh```` progress on a CVM.
  3. __Browser:__ Reload the PE URL, accept security override, login as admin and password to PE EULA.
  4. __Terminal:__ Once PE UI configured, reload browser to show EULA bypassed or decline EULA.
    - *BUG:* Once Authentication Server is up, you can login as a SSP admin = adminuser05@ntnxlab.local
  5. __Browser:__
    - Show PE Authentication: test above user with the default password.
    - View All Tasks, wait until software is uploading
  6. __Terminal:__ Show that we're waiting...approximately 17 minutes (fast forward)
    - Highlight automation scripts sent to PC
  7. __Browser:__ from PE, show VM table, go to home and show PE registered to PC, launch PC and login as admin.
    * *BUG:* Can't login as a SSP admin = adminuser05@ntnxlab.local
    * Show Authentication, show role mapping, show images.
0. Push button Calm!
  1. __PC> Apps:__ click lower left ? to show Calm 5.7
      * *BUG* why a ? in the UI?
  2. __Projects:__ Default: add the following:
    - Description: "Freedom to Cloud",
    - Roles: assign and save,
    - Local and Cloud,
    - choose PoC AHV cluster,
    - Network: enable VLANs,
    - and Save.
  3. __Blueprints:__ Upload blueprint: ````beachhead-centos7-calm5.7.0.1.json```` in default project.
    - Resize icon
    - Pull left tab open, note public key in AHVCluster application profile, zoom to show end of the value.
    - __Credentials:__ upload private key, note user centos, save, back.
    - __Service = Webtier:__
        - Show VM name, zoom in to show macros.
        - Choose local image uploaded to cluster to save time versus the dynamic imported image.
        - Show user centos in cloud-init and @@{your_public_key}@@ macro.
        - Show package install task: uncomment install work
        - Show service tab: Deployment Config
          - *bug* service > service is redundant!
        - Save, Launch!
  4. __Application Launch:__
    - Name application deployment: marklavi-beachhead-took-X-minutes
    - Terminal: find start time, find end time.
      - *BUG:* time zones of server, cloud-init?
    - Show logical deployment, open terminal, audit logs
