'use strict';

const Knex = require('knex');
const fs = require('fs');

// createTcpPool initializes a TCP connection pool for a Cloud SQL
// instance of Postgres.
const createTcpPool = async (config) => {
  // Note: Saving credentials in environment variables is convenient, but not
  // secure - consider a more secure solution such as
  // Cloud Secret Manager (https://cloud.google.com/secret-manager) to help
  // keep secrets safe.
  const dbConfig = {
    client: 'pg',
    connection: {
      host: process.env.INSTANCE_HOST, // e.g. '127.0.0.1'
      port: process.env.DB_PORT, // e.g. '5432'
      user: process.env.DB_USER, // e.g. 'my-user'
      password: process.env.DB_PASS, // e.g. 'my-user-password'
      database: process.env.DB_NAME, // e.g. 'my-database'
    },
    // ... Specify additional properties here.
    ...config,
  };

  // (OPTIONAL) Configure SSL certificates
  // For deployments that connect directly to a Cloud SQL instance without
  // using the Cloud SQL Proxy, configuring SSL certificates will ensure the
  // connection is encrypted.
  if (process.env.DB_ROOT_CERT) {
    dbConfig.connection.ssl = {
      rejectUnauthorized: false,
      ca: fs.readFileSync(process.env.DB_ROOT_CERT), // e.g., '/path/to/my/server-ca.pem'
      key: fs.readFileSync(process.env.DB_KEY), // e.g. '/path/to/my/client-key.pem'
      cert: fs.readFileSync(process.env.DB_CERT), // e.g. '/path/to/my/client-cert.pem'
    };
  }
  // Establish a connection to the database.
  return Knex(dbConfig);
};

module.exports = createTcpPool;
