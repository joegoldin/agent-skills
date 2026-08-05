# Start the ingest service

1. Open a terminal on the host.
2. If the pool is not ready, start the pool first.
3. Run the command `sqlpipe start`.
4. Make sure that the log shows the line "ready".

The service reads the configuration file at start. The file gives the port and
the pool size. The service writes one log line for each request.
