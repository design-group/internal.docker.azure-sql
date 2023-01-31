#!/bin/bash

export SQLCMDPASSWORD=${SA_PASSWORD:-$(< "${SA_PASSWORD_FILE}")}

sqlcmd -S localhost -U sa -l 3 -V 16 -Q "SELECT 1"