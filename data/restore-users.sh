#!/bin/bash

/opt/couchbase/bin/cbimport json -c couchbase://localhost -u $1 -p $2 -b gluu_user -f lines -g "%cbkey%" --ignore-fields cbkey -d file://$3

