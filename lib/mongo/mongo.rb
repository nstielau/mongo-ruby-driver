# --
# Copyright (C) 2008-2009 10gen Inc.
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU Affero General Public License, version 3, as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License
# for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
# ++

require 'mongo/db'

module XGen
  module Mongo
    module Driver

      # Represents a Mongo database server.
      class Mongo

        DEFAULT_PORT = 27017

        # Create a Mongo database server instance. You specify either one or a
        # pair of servers. If one, you also say if connecting to a slave is
        # OK. In either case, the host default is "localhost" and port default
        # is DEFAULT_PORT.
        #
        # If you specify a pair, pair_or_host is a hash with two keys :left
        # and :right. Each key maps to either
        # * a server name, in which case port is DEFAULT_PORT
        # * a port number, in which case server is "localhost"
        # * an array containing a server name and a port number in either order
        #
        # +options+ are passed on to each DB instance:
        #
        # :slave_ok :: Only used if one host is specified. If false, when
        #              connecting to that host/port a DB object will check to
        #              see if the server is the master. If it is not, an error
        #              is thrown.
        #
        # :auto_reconnect :: If a DB connection gets closed (for example, we
        #                    have a server pair and saw the "not master"
        #                    error, which closes the connection), then
        #                    automatically try to reconnect to the master or
        #                    to the single server we have been given. Defaults
        #                    to +false+.
        #
        # Since that's so confusing, here are a few examples:
        #
        #  Mongo.new                         # localhost, DEFAULT_PORT, !slave
        #  Mongo.new("localhost")            # localhost, DEFAULT_PORT, !slave
        #  Mongo.new("localhost", 3000)      # localhost, 3000, slave not ok
        #  # localhost, 3000, slave ok
        #  Mongo.new("localhost", 3000, :slave_ok => true)
        #  # localhost, DEFAULT_PORT, auto reconnect
        #  Mongo.new(nil, nil, :auto_reconnect => true)
        #
        #  # A pair of servers. DB will always talk to the master. On socket
        #  # error or "not master" error, we will auto-reconnect to the
        #  # current master.
        #  Mongo.new({:left  => ["db1.example.com", 3000],
        #             :right => "db2.example.com"}, # DEFAULT_PORT
        #            nil, :auto_reconnect => true)
        #
        #  # Here, :right is localhost/DEFAULT_PORT. No auto-reconnect.
        #  Mongo.new({:left => ["db1.example.com", 3000]})
        #
        # When a DB object first connects to a pair, it will find the master
        # instance and connect to that one.
        def initialize(pair_or_host=nil, port=nil, options={})
          @pair = case pair_or_host
                   when String
                     [[pair_or_host, port || DEFAULT_PORT]]
                   when Hash
                    connections = []
                    connections << pair_val_to_connection(pair_or_host[:left])
                    connections << pair_val_to_connection(pair_or_host[:right])
                    connections
                   when nil
                     [['localhost', DEFAULT_PORT]]
                   end
          @options = options
        end

        # Return the XGen::Mongo::Driver::DB named +db_name+. The slave_ok and
        # auto_reconnect options passed in via #new may be overridden here.
        # See DB#new for other options you can pass in.
        def db(db_name, options={})
          XGen::Mongo::Driver::DB.new(db_name, @pair, @options.merge(options))
        end

        # Returns a hash containing database names as keys and disk space for
        # each as values.
        def database_info
          doc = single_db_command('admin', :listDatabases => 1)
          h = {}
          doc['databases'].each { |db|
            h[db['name']] = db['sizeOnDisk'].to_i
          }
          h
        end

        # Returns an array of database names.
        def database_names
          database_info.keys
        end

        # Not implemented.
        def clone_database(from)
          raise "not implemented"
        end

        # Not implemented.
        def copy_database(from_host, from_db, to_db)
          raise "not implemented"
        end

        # Drops the database +name+.
        def drop_database(name)
          single_db_command(name, :dropDatabase => 1)
        end

        protected

        # Turns an array containing an optional host name string and an
        # optional port number integer into a [host, port] pair array.
        def pair_val_to_connection(a)
          case a
          when nil
            ['localhost', DEFAULT_PORT]
          when String
            [a, DEFAULT_PORT]
          when Integer
            ['localhost', a]
          when Array
            connection = ['localhost', DEFAULT_PORT]
            connection[0] = a[0] if a[0].kind_of?(String)
            connection[0] = a[1] if a[1].kind_of?(String)
            connection[1] = a[0] if a[0].kind_of?(Integer)
            connection[1] = a[1] if a[1].kind_of?(Integer)
            connection
          end
        end

        # Send cmd (a hash, possibly ordered) to the admin database and return
        # the answer. Raises an error unless the return is "ok" (DB#ok?
        # returns +true+).
        def single_db_command(db_name, cmd)
          db = nil
          begin
            db = db(db_name)
            doc = db.db_command(cmd)
            raise "error retrieving database info: #{doc.inspect}" unless db.ok?(doc)
            doc
          ensure
            db.close if db
          end
        end

      end
    end
  end
end

