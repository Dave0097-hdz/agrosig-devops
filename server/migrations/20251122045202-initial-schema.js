'use strict';

var dbm;
var type;
var seed;
var fs = require('fs');
var path = require('path');

/**
  * We receive the dbmigrate dependency from dbmigrate initially.
  * This enables us to not have to rely on NODE_PATH.
  */
exports.setup = function (options, seedLink) {
  dbm = options.dbmigrate;
  type = dbm.dataType;
  seed = seedLink;
};

exports.up = function (db) {
  var filePath = path.join(__dirname, 'sql', 'initial-schema-up.sql');
  var sql = fs.readFileSync(filePath, { encoding: 'utf-8' });
  return db.runSql(sql);
};

exports.down = function (db) {
  return null;
};

exports._meta = {
  "version": 1
};
