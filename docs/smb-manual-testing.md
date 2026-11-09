# Manual SMB test procedure

Use a non-production test SMB server and a dedicated test account. Verify against an Apple Silicon Mac and an Intel Mac when both are available.

1. Deploy `/Library/Application Support/SMBConnector/servers.json` with one valid test server. Confirm the application loads the server and its reachability indicator changes independently of credentials.
2. Launch the Debug app with `SMB_CONNECTOR_USE_REAL_SMB=1`.
3. Enter a valid username and password without enabling “Remember.” Connect and confirm the share list contains only disk shares visible to that account.
4. Connect with an invalid password. Confirm the app reports a retryable authentication error without displaying raw tool output.
5. Connect with an account that can authenticate but has no share access. Confirm the required empty-state message is shown in the same panel.
6. Select a share with a space in its name and mount it. Confirm the mount appears under `/Volumes/<share-name>` and in Finder.
7. Enable “Remember,” connect successfully, and confirm the password is saved under the `SMBConnector/<server-id>` Keychain service for that username. Update the password, reconnect, and confirm the saved item updates. Uncheck “Remember” and connect successfully to remove the saved item. Confirm a later connection still works when entered manually.
8. Disconnect the server or block TCP port 445. Confirm availability becomes unavailable/error without implying anything about authorization.
9. Inspect app logs and process listings during these operations. Confirm no password is logged, placed in process arguments, or embedded in an SMB URL.
10. Remove the test mount and Keychain test item after the procedure.

Real-server tests require an authorized SMB server and credentials; the automated suite uses mocks and does not attempt network access.
