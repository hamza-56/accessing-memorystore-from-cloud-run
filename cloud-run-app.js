/**
 * Cloud Run application that generates and delivers dynamically generated content.
 */

const express = require('express');
const cors = require('cors')
const redis = require('redis');

const createTcpPool = require('./connect-tcp.js');
const createUnixSocketPool = require('./connect-unix.js');

const app = express();

const client = redis.createClient({
  'host': process.env.REDIS_IP
});
client.on('error', function(error) {
  console.error(error);
});

// Set up a variable to hold our connection pool. It would be safe to
// initialize this right away, but defering its instantiation to ease
// testing different configurations.
let pool;

// Initialize Knex, a Node.js SQL query builder library with built-in connection pooling.
const createPool = async () => {
    // Configure which instance and what database user to connect with.
    // Remember - storing secrets in plaintext is potentially unsafe. Consider using
    // something like https://cloud.google.com/kms/ to help keep secrets secret.
    const config = {pool: {}};
  
    // 'max' limits the total number of concurrent connections this pool will keep. Ideal
    // values for this setting are highly variable on app design, infrastructure, and database.
    config.pool.max = 5;
    // 'min' is the minimum number of idle connections Knex maintains in the pool.
    // Additional connections will be established to meet this value unless the pool is full.
    config.pool.min = 5;
  
    // 'acquireTimeoutMillis' is the number of milliseconds before a timeout occurs when acquiring a
    // connection from the pool. This is slightly different from connectionTimeout, because acquiring
    // a pool connection does not always involve making a new connection, and may include multiple retries.
    // when making a connection
    config.pool.acquireTimeoutMillis = 60000; // 60 seconds
    // 'createTimeoutMillis` is the maximum number of milliseconds to wait trying to establish an
    // initial connection before retrying.
    // After acquireTimeoutMillis has passed, a timeout exception will be thrown.
    config.pool.createTimeoutMillis = 30000; // 30 seconds
    // 'idleTimeoutMillis' is the number of milliseconds a connection must sit idle in the pool
    // and not be checked out before it is automatically closed.
    config.pool.idleTimeoutMillis = 600000; // 10 minutes
  
    // 'knex' uses a built-in retry strategy which does not implement backoff.
    // 'createRetryIntervalMillis' is how long to idle after failed connection creation before trying again
    config.pool.createRetryIntervalMillis = 200; // 0.2 seconds

    if (process.env.INSTANCE_HOST) {
        // Use a TCP socket when INSTANCE_HOST (e.g., 127.0.0.1) is defined
        return createTcpPool(config);
    } else if (process.env.INSTANCE_UNIX_SOCKET) {
        // Use a Unix socket when INSTANCE_UNIX_SOCKET (e.g., /cloudsql/proj:region:instance) is defined.
        return createUnixSocketPool(config);
    } else {
        throw 'One of INSTANCE_HOST or INSTANCE_UNIX_SOCKET` is required.';
    }
};

app.use(cors());

app.get('/', async (req, res) => {
  res.set('Cache-Control', 'no-store');
  client.set('key', 'value!', redis.print);

  pool = pool || (await createPool());
  let tableNames = '<em style="color:red;>PostgreSQL not connected</em>';

  try {
    tableNames = await pool('pg_catalog.pg_tables')
        .select('tablename');
    
    tableNames = tableNames.map(obj => obj.tablename).join(', ');

    } catch(err) {
        console.error(err);
    }

  client.get('key', (err, reply) => {
    res.send(`
    <html>
      <head>
      </head>
      <body>
        <h2>Redis Connection Test</h2>
        <p>Connecting to Redis at: ${process.env.REDIS_IP}</p>
        <p>Value of key just read: ${reply}</p>
        <hr>
        <h2>Cloud SQL Connection Test</h2>
        <p>Database table names: ${tableNames}<p>
      </body>
    </html>
    `);
    });
  });


const port = process.env.PORT || 8080;
app.listen(port, () => {
  console.log(`Listening on port ${port}`);
});