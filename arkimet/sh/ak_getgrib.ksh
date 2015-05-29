#/bin/ksh
#--------------------------------------------------------------------------
# Procedura per estrarre da un dataset Arkimet una serie di Grib 
#
# Per modificare i path del pacchetto ma_utils, assegnare le variabili:
# MA_UTILS_DAT: tabelle ma_utils (ad esempio: /home/eminguzzi/svn/ma_utils/data;
#               se non specificato, usa: /usr/share/ma_utils)
# MA_UTILS_SVN: eseguibili (ad esempio: /home/eminguzzi/svn/ma_utils; se non 
#               specificato, usa gli eseguibili in: /usr/libexec/ma_utils)
#
# Per modificare i path di pacchetti libsim/dballe, assegnare le variabili:
# LIBSIM_DATA:  tabelle libsim (se non specificato usa: /usr/share/libsim)
# DBA_TABLES:   tabelle dballe (se non specificato usa: /usr/share/wreport)
# LIBSIM_SVN:   eseguibili (ad esempio: /home/eminguzzi/svn/libsim; se non 
#               specificato, usa gli eseguibili in path)
#
#                                         Versione 2.0.1, Enrico 29/04/2015
#--------------------------------------------------------------------------
#set -x

#--------------------------------------------------------------------------
# Scrive a schermo l'help della procedura
function write_help
{
#       123456789012345678901234567890123456789012345678901234567890123456789012345
  echo ""
  echo "Uso: ak_getgrib.ksh PROGETTO DATASET [-arc=URL] [-h]"
  echo "Estrae un gruppo di grib da un archivio arkimet, senza compiere elaborazioni"
  echo ""
  echo "PROGETTO: legge la query arkimet dal file PROGETTO.akq (esempi in "
  echo "          ~eminguzzi/arkimet/templates/template.akq.DATASET)"
  echo "DATASET:  nome del dataset da cui estrarre;"
  echo "          per query multi-dataset, sintassi DS1%DS2"
  echo "-arc=URL  accede al server Arkimet specificato:"
  echo "          archivio centrale SIMC: http://arkimet.metarpa:8090 (default)"
  echo "          archivio backup maialinux: http://maialinux.metarpa:8090"
  echo "          archivio locale MA: /autofs/scratch2/eminguzzi/tmp/local_arkimet"
  echo "-zoom=LON_MIN,LAT_MIN,LON_MAX,LAT_MAX: ritaglia (lato client) una sottoarea "
  echo "-mon=FILE scrive su FILE le date estratte, man man che vengono elaborate"
  echo "          (se usato senza opzione -zoom potrebbe rallentare l'estrazione)"
  echo "-h:       visualizza questo help"
  echo ""
  echo "Per usare versioni di lavoro di programmi e tabelle, esportare le variabili:"
  echo "          MA_UTILS_DAT, MA_UTILS_SVN, LIBSIM_DATA, DBA_TABLES, LIBSIM_SVN"
  echo ""
#       123456789012345678901234567890123456789012345678901234567890123456789012345
  return
}

#--------------------------------------------------------------------------
# 1) Preliminari

# 1.1) Parametri da riga comando e controlli

if [ $# -eq 0 ] ; then
  write_help
  exit 1
fi

split="N"
zoom="N"
mon="N"
filemon=""
akurl="http://arkimet.metarpa:8090"
local_aliases=/autofs/nethomes/eminguzzi/arkimet/dat/match-alias.conf.local
split_opt="--time-interval=day"

mand_par=0
while [ $# -ge 1 ] ; do
  if [ $1 = '-h' ] ; then
    write_help
    exit 1
  elif [ `echo $1 | awk '{print substr($1,1,4)}'` = '-arc' ] ; then
    akurl=`echo $1 | cut -d = -f 2`
    shift
  elif [ `echo $1 | awk '{print substr($1,1,4)}'` = '-mon' ] ; then
    mon="Y"
    filemon=`echo $1 | cut -d = -f 2`
    rm -f $filemon
    shift
  elif [ `echo $1 | awk '{print substr($1,1,5)}'` = '-zoom' ] ; then
    zoom="Y"
    str_zoom=`echo $1 | cut -d = -f 2`
    lon_min=`echo $str_zoom | cut -d , -f 1`
    lat_min=`echo $str_zoom | cut -d , -f 2`
    lon_max=`echo $str_zoom | cut -d , -f 3`
    lat_max=`echo $str_zoom | cut -d , -f 4`
    shift
  elif [ $mand_par -eq 0 ] ; then
    prog=$1
    mand_par=1
    shift
  elif [ $mand_par -eq 1 ] ; then
    ds=$1
    mand_par=2
    shift
  else
    echo "Skip parametro non gestito "$1
    shift
  fi
done

# Controlli sui parametri
if [ $mand_par -ne 2 ] ; then
  write_help
  exit 1
fi
if [ $zoom = "Y" -o $mon = "Y" ] ; then
  split="Y"
fi

# 1.2 Path e utility
if [ -z $MA_UTILS_SVN ] ; then
  test_1grib=/usr/libexec/ma_utils/test_1grib.exe
else
  echo "(ak_getgrib.ksh) Eseguibili ma_utils: copia di lavoro in "$MA_UTILS_SVN
  test_1grib=${MA_UTILS_SVN}/util/grib/src/test_1grib.exe
fi

# 1.3 Segnalo eventuali variabili d'ambiente assegnate a valori non di default
if [ ! -z $LIBSIM_SVN ] ; then
  echo "(ak_getgrib.ksh) Eseguibili libsim: copia di lavoro in "$LIBSIM_SVN
fi
if [ ! -z $MA_UTILS_DAT ] ; then
  echo "(ak_getgrib.ksh) Tabelle ma_utils: copia di lavoro in "$MA_UTILS_DAT
fi
if [ ! -z $LIBSIM_DATA ] ; then
  echo "(ak_getgrib.ksh) Tabelle libsim: copia di lavoro in "$LIBSIM_DATA
fi
if [ ! -z $DBA_TABLES ] ; then
  echo "(ak_getgrib.ksh) Tabelle dballe: copia di lavoro in "$DBA_TABLES
fi

# 1.4 Altri preliminari
if [ ! -z $http_proxy ] ; then
  unset http_proxy
fi

is_local=`echo $akurl | grep "http" | wc -l`
if [ $is_local -eq 0 ] ; then
  echo "Richiesta estrazione da un DB locale, uso gli alias in "$local_aliases
  export ARKI_ALIASES=$local_aliases
fi

# Maiuscole/minuscole nel nome del dataset (arkimet: minusc.; maialinux: maiusc.)
if [ `echo $akurl | grep "arkimet.metarpa" | wc -l` -eq 1 ] ; then      # arkimet
  ds=`echo $ds | tr '[:upper:]' '[:lower:]'`
elif [ `echo $akurl | grep "maialinux.metarpa" | wc -l` -eq 1 ] ; then  # maialinux
  ds=`echo $ds | tr '[:lower:]' '[:upper:]'`
fi 

#--------------------------------------------------------------------------
# 2) Elaborazioni

rm -f ${prog}.akq.proc ${prog}.query.* ${ds}.conf ${prog}.grb

# 2.1 Costriusco il config
rm -f ${ds}.conf
nsep=`echo $ds | awk '{print gsub("%","###",$1)}'`
cntds=0
while [ $cntds -le $nsep ] ; do
  cntds=`expr $cntds + 1`
  dsc=`echo $ds | cut -d % -f $cntds`
  arki-mergeconf ${akurl}/dataset/${dsc} >> ${ds}.conf 2>/dev/null
  if [ $? -ne 0 ] ; then
    echo "Errore nell'accesso al dataset: ${akurl}/dataset/${dsc}"
    exit 3
  fi
done

# 2.2 Elaboro il file con i dati richiesti (.akq)

# Filtro commenti e righe vuote
grep -Ev "^ *$" ${prog}.akq | grep -v ^! > ${prog}.akq.proc

# Filtro i separatori e scrivo le query in files separati
cntq=1
while read line ; do
  echo $line | grep \# > /dev/null
  if [ $? -eq 0 ] ; then                 # trovato separatore: nuova query
    cntq=`expr $cntq + 1`
  else                                   # mantengo query corrente
    echo $line >> ${prog}.query.${cntq}
  fi
done < ${prog}.akq.proc

echo "Pronto per estrarre, lancero' "$cntq" query"

# 2.3 Se richiesto, costruisco lo script per arki-xargs
if [ $split = "Y" ] ; then
  rm -f xargs.ksh
  echo "rm -f tmp.grb" >> xargs.ksh
  if [ $zoom = "Y" ] ; then
    echo "vg6d_subarea --trans-type=zoom --sub-type=coordbb --ilon=$lon_min --ilat=$lat_min --flon=$lon_max --flat=$lat_max \$2 tmp.grb" >> xargs.ksh
  else
    echo mv $2 tmp.grb
  fi
  if [ $mon = "Y" ] ; then
    echo "curr_date=\`grib_get -P dataDate tmp.grb | head -n 1\`" >> xargs.ksh
    echo "echo \$curr_date >> $filemon" >> xargs.ksh
  fi
  echo "cat tmp.grb >> \$1" >> xargs.ksh
  chmod +x xargs.ksh
fi

# 2.4 Estraggo
cnt=1
while [ $cnt -le $cntq ] ; do
  echo "Elaboro query "$cnt"      "`date "+%Y%m%d %H:%M:%S"`
  if [ $split = "Y" ] ; then
    arki-query --config=${ds}.conf --file=${prog}.query.${cnt} --inline | \
      arki-xargs ${split_opt} ./xargs.ksh ${prog}.grb 
  elif [ $split = "N" ] ; then
    arki-query --config=${ds}.conf --file=${prog}.query.${cnt} --data >> ${prog}.grb 
  fi
  cnt=`expr $cnt + 1`
done

# 2.5 controllo edition
if [ -s ${prog}.grb ] ; then
  en=`$test_1grib ${prog}.grb | cut -d , -f 1`
  if [ $en -eq 2 ] ; then
    mv ${prog}.grb ${prog}.grib2
  fi
  echo "Estrazione terminata "`date "+%Y%m%d %H:%M:%S"`
else
  echo "Non ho trovato nulla!!  "`date "+%Y%m%d %H:%M:%S"`
fi
