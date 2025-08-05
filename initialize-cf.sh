cf login -u admin -p TtJG49fUYVaFU-4l6K_T1hfsQP60_Rx8

cf create-org banzai
cf create-space -o banzai dev
cf create-user tanzu Tanzu1!
cf set-space-role tanzu banzai dev SpaceDeveloper
