# Connection timeouts

If sqlpipe hangs or fails with a timeout, you should check that the host running
sqlpipe can reach the Postgres port; this is often a security group rule that is
blocking the connection, making the client wait.

The migration has been completed and the table is being rebuilt by the worker.

You'll want to grab the API key from the dashboard before configuring the client,
which you can do under Settings, e.g. the admin page.

Set up the pool and turn on logging. Leverage the config to utilize the settings.
Verify the value, then validate the configuration.

Increase the timeout if the network is slow.

Ensure file exists before running. The pool opens. The worker starts. The queue
drains. The log rotates. The lock clears. The service reports ready. The metrics
flush.
