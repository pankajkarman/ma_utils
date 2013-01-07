PROGRAM proc_multi_orari
!--------------------------------------------------------------------------
! Data una lista di files relativi a serie storiche su punto, scrive un
! file che per ogni data/parametro contiene il risultato di una statistica
! sui files di input.
! Gestisce i formati seriet (decimale ed exp), estra_orari, estra_qa 
! (orario e giornaliero), trasp_temp
!
! Uso: 
! proc_orari.exe [-h] [-s/-sx/-q/-t] filelst stat fileout
!
! Per aggiungere una nuova elaborazione "custom", modificare:
! - controlli sui parametri (par 1.1 in fondo)
! - controlli sui dati in input (par 1.5)
! - calcoli (par 2.2)
! - help (subr. scrive_help)
!
! Note:
! - Tutti i files di input devono essere nello stesso formato, contenere gli
!   stessi istanti e gli stessi parametri (nello stesso ordine e con lo 
!   stesso nome)
! - Il programma elabora ogni dato in modo indipendente (ad esempio, non fa 
!   nessun tipo di controllo sulla sequenzialita' delle date)
!
! TODO:
! - gestire il numero di decimali in ouput (ora e' un parametro costante)
! - aggiungere diagnostica complessiva (es. dati validi totali in/out)
!
!                                                 V2.0.0, Enrico 03/09/2012
!--------------------------------------------------------------------------

USE array_utilities
IMPLICIT NONE

!==========================================================================
! 0) Dichiarazioni

! Parametri costanti
REAL, PARAMETER :: rmis_hhr = -9999. ! dato mancante, files estra_orari
REAL, PARAMETER :: rmis_ser = -9999. ! dato mancante, files trasp_seriet
REAL, PARAMETER :: rmis_sex = -1.E30 ! dato mancante, files trasp_seriet exp
REAL, PARAMETER :: rmis_qad = -9999. ! dato mancante, files estra_qa giorn.
REAL, PARAMETER :: rmis_tem = -9999. ! dato mancante, files trasp_temp
INTEGER, PARAMETER :: fw = 10        ! ampiezza dei campi nei files I/O
INTEGER, PARAMETER :: mxpar = 500    ! n.ro max di parametri in un file
INTEGER, PARAMETER :: iulst = 20     ! unita' per filelst
INTEGER, PARAMETER :: iuout = 25     ! unit' per fileout
INTEGER, PARAMETER :: iu0 = 30       ! prima unita' per i files di input
INTEGER, PARAMETER :: out_dec = 1    ! n.ro di decimali in output

! Altre variabili del programma
REAL, ALLOCATABLE :: val_in(:,:),val_out(:),nok(:),val_ok(:),ave(:),ave2(:)
REAL :: rmis
INTEGER :: mand_par,eof,eor,ios,nf,npar,head_len,head_offset,nhead,nld
INTEGER :: yy,mm,dd,hh,sca,idx
INTEGER :: kp,kr,kf,p1,p2

CHARACTER (LEN=mxpar*(fw+1)+20) :: head_par,head_liv,head_par1,head_liv1
CHARACTER (LEN=mxpar*(fw+1)+20) :: head_par_out,head_liv_out
CHARACTER (LEN=fw), ALLOCATABLE :: chval(:)
CHARACTER (LEN=fw) :: idpar(mxpar)
CHARACTER (LEN=250) :: filelst,chdum,filein,fileout,chfmt1,chfmt2
CHARACTER (LEN=3) :: stat,inp_data
LOGICAL :: ld

!==========================================================================
! 1) Preliminari

!--------------------------------------------------------------------------
! 1.1 Parametri da riga comando

inp_data = "nil"
mand_par = 0
filelst = ""
ld = .FALSE.

DO kp = 1,HUGE(0)
  CALL getarg(kp,chdum)
  IF (TRIM(chdum) == "") THEN
    EXIT
  ELSE IF (TRIM(chdum) == "-h") THEN
    CALL scrive_help
    STOP
  ELSE IF (TRIM(chdum) == "-o") THEN
    inp_data = "hhr"
  ELSE IF (TRIM(chdum) == "-s") THEN
    inp_data = "ser"
  ELSE IF (TRIM(chdum) == "-sx") THEN
    inp_data = "sex"
  ELSE IF (TRIM(chdum) == "-q") THEN
    inp_data = "qad"
  ELSE IF (TRIM(chdum) == "-t") THEN
    inp_data = "tem"
  ELSE IF (TRIM(chdum) == "-ld") THEN
    ld = .TRUE.
  ELSE
    IF (mand_par == 0) THEN
      filelst = TRIM(chdum)
    ELSE IF (mand_par == 1) THEN
      stat = TRIM(chdum)
    ELSE IF (mand_par == 2) THEN
      fileout = TRIM(chdum)
    ENDIF
    mand_par = mand_par + 1
  ENDIF
ENDDO

IF (mand_par /= 3 .OR. inp_data == "nil") THEN
  CALL scrive_help
  STOP
ENDIF
IF (stat/="ave" .AND. stat/="max" .AND. stat/="min" .AND. &
    stat/="std" .AND. stat/="mdn" .AND. stat/="tke") THEN
  CALL scrive_help
  STOP
ENDIF

!--------------------------------------------------------------------------
! 1.2 Parametri dipendenti dal formato dei dati; codice per EOF

IF (inp_data == "hhr") THEN
  head_offset = 13
  nhead = 3
  rmis = rmis_hhr
ELSE IF (inp_data == "ser") THEN
  head_offset = 17
  nhead = 6
  rmis = rmis_ser
ELSE IF (inp_data == "sex") THEN
  head_offset = 17
  nhead = 6
  rmis = rmis_sex
ELSE IF (inp_data == "qad") THEN
  head_offset = 10
  nhead = 3
  rmis = rmis_qad
ELSE IF (inp_data == "tem") THEN
  head_offset = 19
  nhead = 3
  rmis = rmis_tem
ENDIF

CALL get_eof_eor(eof,eor)

!--------------------------------------------------------------------------
! 1.3 Apro i files di input

OPEN (UNIT=iulst, FILE=filelst, STATUS="OLD", FORM="FORMATTED", ERR=9999)
DO nf = 1,HUGE(0)
  READ (iulst,'(a)',IOSTAT=ios) filein
  IF (ios == eof) EXIT
  OPEN (UNIT=iu0+nf, FILE=filein, STATUS="OLD", FORM="FORMATTED", ERR=9998)
ENDDO  
nf = nf - 1
CLOSE (iulst)
IF (nf < 1) GOTO 9998

!--------------------------------------------------------------------------
! 1.4 Leggo gli header (parametri e livelli) dei files in input e controllo
!     che siano uguali per tutti i files

nld = 0
DO kf = 1,nf

! Leggo gli header
  IF (inp_data == "hhr") THEN
    READ (iu0+kf,*,ERR=9997)
    READ (iu0+kf,*,ERR=9997)
    READ (iu0+kf,'(a)', ERR=9997) head_par
    head_liv = ""
  
  ELSE IF (inp_data == "ser" .OR. inp_data == "sex") THEN
    READ (iu0+kf,*,ERR=9997)
    READ (iu0+kf,*,ERR=9997)
    READ (iu0+kf,*,ERR=9997)
    READ (iu0+kf,'(a)',ERR=9997) head_liv
    READ (iu0+kf,*,ERR=9997)
    READ (iu0+kf,'(a)',ERR=9997) head_par
  
  
  ELSE IF (inp_data == "qad") THEN
    READ (iu0+kf,*,ERR=9997)
    READ (iu0+kf,*,ERR=9997)
    READ (iu0+kf,'(a)', ERR=9997) head_par
    head_liv = ""
  
  ELSE IF (inp_data == "tem") THEN
    READ (iu0+kf,'(a)',ERR=9997) head_liv
    READ (iu0+kf,*,ERR=9997)
    READ (iu0+kf,'(a)', ERR=9997) head_par
  
  ENDIF

! Controllo che siano uguali a quelli del primo file
  IF (kf == 1) THEN
    head_liv1 = head_liv
    head_par1 = head_par
  ELSE
    IF (TRIM(head_liv1) /= TRIM(head_liv)) THEN
      IF (ld) THEN
        nld = nld + 1
      ELSE
        GOTO 9996
      ENDIF
    ENDIF
    IF (TRIM(head_par1) /= TRIM(head_par)) GOTO 9995
  ENDIF

ENDDO

! Calcolo il numero dei parametri
head_len = LEN(TRIM(head_par1))
IF (MOD(head_len - head_offset, fw + 1) /= 0) THEN
  GOTO 9994
ELSE
  npar = (head_len - head_offset) / (fw + 1)
ENDIF

! Leggo le stringhe identificative dei parametri
idpar(:) = ""
DO kp = 1, npar
  p1 = head_offset + (fw+1)*(kp-1) + 2
  p2 = head_offset + (fw+1)*kp
  READ (head_par1(p1:p2),'(a)') idpar(kp)
ENDDO

!--------------------------------------------------------------------------
! 1.5 Controllo che i dati in input siano compatibili con l'elaborazione
!     richiesta; se necessario, modifico gli header in output

head_par_out = head_par1
head_liv_out = head_liv1

IF (stat =="tke") THEN
  IF (nf /= 1) THEN
    WRITE (*,*) "La statistica ""tke"" richiede un solo file in input"
    GOTO 9991
  ENDIF
  DO kp = 1,npar
    IF (INDEX(idpar(kp),"tke") == 0) THEN
      WRITE (*,*) "Trovato parametro non tke: ",kp
      GOTO 9991
    ENDIF
  ENDDO

  DO kp = 1, npar
    p1 = head_offset + (fw+1)*(kp-1) + 2
    p2 = head_offset + (fw+1)*kp
    WRITE (head_par_out(p1:p2),'(a)') "  real-tke"
  ENDDO
ENDIF

!--------------------------------------------------------------------------
! 1.6 Costruisco i formati per i dati in input (chftm1) e output (chfmt2)

IF (inp_data == "hhr") THEN
  WRITE (chfmt1,'(a,2(i3.3,a))') "(i4,3i3,",npar,"(1x,a",fw,"))"
  WRITE (chfmt2,'(a,3(i3.3,a))') "(i4.4,3(1x,i2.2),", &
    npar,"(1x,f",fw,".",out_dec,"))"

ELSE IF (inp_data == "qad") THEN
  WRITE (chfmt1,'(a,2(i3.3,a))') "(i4,2i3,",npar,"(1x,a",fw,"))"
  WRITE (chfmt2,'(a,3(i3.3,a))') "(i4.4,2(1x,i2.2),", &
    npar,"(1x,f",fw,".",out_dec,"))"

ELSE IF (inp_data == "tem") THEN
  WRITE (chfmt1,'(a,2(i3.3,a))') "(i4,3i3,6x,",npar,"(1x,a",fw,"))"
  WRITE (chfmt2,'(a,3(i3.3,a))') "(i4.4,3(1x,i2.2),6x,", &
    npar,"(1x,f",fw,".",out_dec,"))"

ELSE IF (inp_data == "ser") THEN
  WRITE (chfmt1,'(a,2(i3.3,a))') "(i2,1x,i2,1x,i4,1x,i2,1x,i3,", &
    npar,"(1x,a",fw,"))"
  WRITE (chfmt2,'(a,3(i3.3,a))') "(2(i2.2,a1),i4.4,1x,i2.2,1x,i3.3,", &
    npar,"(1x,f",fw,".",out_dec,"))"

ELSE IF (inp_data == "sex") THEN
  WRITE (chfmt1,'(a,2(i3.3,a))') "(i2,1x,i2,1x,i4,1x,i2,1x,i3,", &
    npar,"(1x,a",fw,"))"
  WRITE (chfmt2,'(a,3(i3.3,a))') "(2(i2.2,a1),i4.4,1x,i2.2,1x,i3.3,", &
    npar,"(1x,e",fw,".",3,"))"

ENDIF

!--------------------------------------------------------------------------
! 1.7 Alloco gli arrays

ALLOCATE (val_in(nf,npar),val_ok(nf))
ALLOCATE (val_out(npar),chval(npar),nok(npar),ave(npar),ave2(npar))

!--------------------------------------------------------------------------
! 1.8 Apro il file di output e scrivo gli header

OPEN (UNIT=iuout, FILE=fileout, STATUS="REPLACE", FORM="FORMATTED")

IF (inp_data == "hhr") THEN
  WRITE (iuout,*)
  WRITE (iuout,*)
  WRITE (iuout,'(a)') TRIM(head_par_out)
  head_liv = ""

ELSE IF (inp_data == "ser" .OR. inp_data == "sex") THEN
  WRITE (iuout,*)
  WRITE (iuout,*)
  WRITE (iuout,*)
  WRITE (iuout,'(a)')  TRIM(head_liv_out)
  WRITE (iuout,*)
  WRITE (iuout,'(a)')  TRIM(head_par_out)

ELSE IF (inp_data == "qad") THEN
  WRITE (iuout,*)
  WRITE (iuout,*)
  WRITE (iuout,'(a)')  TRIM(head_par_out)
  head_liv = ""

ELSE IF (inp_data == "tem") THEN
  WRITE (iuout,'(a)')  TRIM(head_liv_out)
  WRITE (iuout,*)
  WRITE (iuout,'(a)') TRIM(head_par_out)

ENDIF

!==========================================================================
! 2) Leggo/scrivo (ciclo sui record in input)

record: DO kr = 1,HUGE(0)

!--------------------------------------------------------------------------
! 2.1 Leggo il prossimo record da tutti i files

  val_in(:,:) = rmis
  DO kf = 1,nf
    IF (inp_data == "hhr") THEN
      READ (iu0+kf,chfmt1,IOSTAT=ios) yy,mm,dd,hh,chval(1:npar)
      IF (ios == eof) EXIT record
      IF (ios /= 0) GOTO 9993
      DO kp = 1,npar
        READ (chval(kp),*,ERR=9992) val_in(kf,kp)
      ENDDO
  
    ELSE IF (inp_data == "qad") THEN
      READ (iu0+kf,chfmt1,IOSTAT=ios) yy,mm,dd,chval(1:npar)
      IF (ios == eof) EXIT record
      hh = 0
      IF (ios /= 0) GOTO 9993
      DO kp = 1,npar
        READ (chval(kp),*,ERR=9992) val_in(kf,kp)
      ENDDO
  
    ELSE IF (inp_data == "ser" .OR. inp_data == "sex") THEN
      READ (iu0+kf,chfmt1,IOSTAT=ios) dd,mm,yy,hh,sca,chval(1:npar)
      IF (ios == eof) EXIT record
      IF (ios /= 0) GOTO 9993
      DO kp = 1,npar
        READ (chval(kp),*,ERR=9992) val_in(kf,kp)
      ENDDO

    ELSE IF (inp_data == "tem") THEN
      READ (iu0+kf,chfmt1,IOSTAT=ios) yy,mm,dd,hh,chval(1:npar)
      IF (ios == eof) EXIT record
      IF (ios /= 0) GOTO 9993
      DO kp = 1,npar
        READ (chval(kp),*,ERR=9992) val_in(kf,kp)
      ENDDO

    ENDIF
  ENDDO

!--------------------------------------------------------------------------
! 2.2 Eseguo l'eleborazione statistica richiesta

  nok(1:npar) = COUNT(val_in(1:nf,1:npar) /= rmis, DIM=1)
  IF (stat == "ave") THEN
    WHERE (nok(1:npar) > 0)
      val_out(1:npar) = SUM(val_in(1:nf,1:npar), DIM=1, &
        MASK=val_in(1:nf,1:npar)/= rmis) / REAL(nok(1:npar))
    ELSEWHERE
      val_out(1:npar) = rmis
    ENDWHERE

  ELSE IF (stat == "max") THEN
    WHERE (nok(1:npar) > 0)
      val_out(1:npar) = MAXVAL(val_in(1:nf,1:npar), DIM=1, &
        MASK=val_in(1:nf,1:npar)/= rmis)
    ELSEWHERE
      val_out(1:npar) = rmis
    ENDWHERE

  ELSE IF (stat == "min") THEN
    WHERE (nok(1:npar) > 0)
      val_out(1:npar) = MINVAL(val_in(1:nf,1:npar), DIM=1, &
        MASK=val_in(1:nf,1:npar)/= rmis)
    ELSEWHERE
      val_out(1:npar) = rmis
    ENDWHERE

  ELSE IF (stat == "std") THEN
    WHERE (nok(1:npar) > 0)
      ave(1:npar) = SUM(val_in(1:nf,1:npar), DIM=1, &
        MASK=val_in(1:nf,1:npar)/= rmis) / REAL(nok(1:npar))
      ave2(1:npar) = SUM(val_in(1:nf,1:npar)**2, DIM=1, &
        MASK=val_in(1:nf,1:npar)/= rmis) / REAL(nok(1:npar))
      val_out(1:npar) = SQRT(MAX(0.,ave(1:npar) - ave2(1:npar)))
    ELSEWHERE
      val_out(1:npar) = rmis
    ENDWHERE

  ELSE IF (stat == "mdn") THEN
    DO kp = 1,npar
      IF (nok(kp) > 0) THEN

!       Salvo i dati validi nel vettore val_ok
        DO kf = 1,nf
          idx = 0
          IF (val_in(kf,kp) /= rmis) THEN
            idx = idx + 1
            val_ok(idx) = val_in(kf,kp)
          ENDIF
        ENDDO
        IF (idx /= nok(kp)) WRITE (*,*) &
          "Errore sorting valori: kf,kp,nok1,nok2 ",kf,kp,nok(kp),idx
   
!       Ordino i valori
        CALL sort(val_ok(1:idx))
   
!       Prendo la mediana
        IF (MOD(idx,2) == 0) THEN
          val_out(kp) = (val_ok(idx/2) + val_ok(idx/2+1)) / 2.
        ELSE
          val_out(kp) = val_ok(idx/2+1)
        ENDIF

      ELSE
        val_out(kp) = rmis

      ENDIF
    ENDDO

  ELSE IF (stat == "tke") THEN
    WHERE (nok(1:npar) > 0)
      val_out(1:npar) = 0.5 * val_in(1,1:npar) * val_in(1,1:npar)
    ELSEWHERE
      val_out(1:npar) = rmis
    ENDWHERE
  ENDIF

!--------------------------------------------------------------------------
! 2.3 Scrivo un record sul file di output

  IF (inp_data == "hhr") THEN
    WRITE (iuout,chfmt2,IOSTAT=ios) yy,mm,dd,hh,val_out(1:npar)

  ELSE IF (inp_data == "qad") THEN
    WRITE (iuout,chfmt2,IOSTAT=ios) yy,mm,dd,val_out(1:npar)

  ELSE IF (inp_data == "ser" .OR. inp_data == "sex") THEN
    WRITE (iuout,chfmt2,IOSTAT=ios) dd,"/",mm,"/",yy,hh,sca,val_out(1:npar)

  ELSE IF (inp_data == "tem") THEN
    WRITE (iuout,chfmt2,IOSTAT=ios) yy,mm,dd,hh,val_out(1:npar)

  ENDIF
  IF (ios /= 0) GOTO 9990

ENDDO record

!==========================================================================
! 3) Conclusione

WRITE (*,'(a,2(i4,a),i6,a)') "Elaborati ",nf," files, ", &
  npar," parametri ",kr-1," istanti"
IF (ld .AND. nld > 0) WRITE (*,'(a,i3,a)') &
  "Warning: le elaborazioni mescolano dati su livelli diversi (in ", &
  nld," files)"

STOP


!==========================================================================
! 4) Gestione errori

9000 CONTINUE
WRITE (*,*) "Il file di input e quello di maschera devono avere lo stesso step temporale"
STOP 10

9999 CONTINUE
WRITE (*,*) "Errore aprendo ",TRIM(filelst)
STOP 1

9998 CONTINUE
WRITE (*,*) "Errore leggendo ",TRIM(filelst)
STOP 2

9997 CONTINUE
WRITE (*,*) "Errore leggendo header, file ",kf
STOP 3

9996 CONTINUE
WRITE (*,*) "Header livelli nel file ",kf," diverso da quello del primo file"
WRITE (*,*) "Header file ",kf,":"
WRITE (*,'(a)') TRIM(head_liv)
WRITE (*,*) "Header primo file:"
WRITE (*,'(a)') TRIM(head_liv1)
STOP 4

9995 CONTINUE
WRITE (*,*) "Header parametri nel file ",kf," diverso da quello del primo file"
STOP 5

9994 CONTINUE
WRITE (*,*) "L'header parametri del primo file e' troncato o ha campi con ampiezza /= ",fw
WRITE (*,*) "lughezza header: ",head_len,", offset: ",head_offset,", fw: ",fw
STOP 6

9993 CONTINUE
WRITE (*,*) "Errore leggendo ",TRIM(filein)," linea ",kr+nhead
STOP 7

9992 CONTINUE
WRITE (*,*) "Errore nella conversione CHAR->REAL ",TRIM(filein), &
  " linea ",kr+nhead
STOP 8

9991 CONTINUE
WRITE (*,*) "Dati di input incompatibili con l'elaborazione richiesta"
STOP 9

9990 CONTINUE
WRITE (*,*) "Errore di scrittura dati, record ",kr

END PROGRAM proc_multi_orari

!$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

SUBROUTINE get_eof_eor(eof, eor)
!-------------------------------------------------------------------------
! Ritorna i codici di errore macchina-dipendenti corrispondenti alle 
! condizioni di EOF e EOR nella lettura di un file sequenziale formattato
!
! Secondo manuale, questi sono gli unici due casi in cui IOSTAT ritorna
! con un valore negativo. 
! Si noti che EOR riguarda solo non-advancinag READ
!-------------------------------------------------------------------------
IMPLICIT NONE

INTEGER, INTENT(OUT) :: eof,eor

INTEGER :: k, ios, idummy=0, iun=0
LOGICAL :: l1 = .TRUE.


! Cerco un'unita' libera per aprire il file di prova
DO k = 10,99
  INQUIRE (UNIT=k, OPENED=l1, IOSTAT=ios)
  IF (.NOT. l1 .AND. ios==0) THEN
    iun = k
    EXIT
  ENDIF
ENDDO
IF (iun == 0) GOTO 9999   ! non ho torvato nessuna unita' libera
!WRITE (*,*) "uso unita ",iun

! Cerco codice di errore per EOF
OPEN (unit=k, STATUS="SCRATCH", FORM="FORMATTED", ACCESS="SEQUENTIAL", &
  PAD="NO", ERR=9999)
ENDFILE (k)
REWIND (k)
READ (k,*,IOSTAT=eof)
CLOSE(k)

! Cerco codice di errore per EOR
OPEN (unit=k, STATUS="SCRATCH", FORM="FORMATTED", ACCESS="SEQUENTIAL", &
  PAD="NO", ERR=9999)
WRITE (k,'(a1)') "1" 
WRITE (k,'(a1)') "2"
REWIND (k)
READ (k,'(i1)',ADVANCE="NO",ERR=9999) idummy
READ (k,'(i1)',ADVANCE="NO",IOSTAT=eor) idummy
CLOSE(k)

!write (*,*) "eof,eor ",eof,eor
RETURN

! Gestione errori
9999 CONTINUE
WRITE (*,*) "Errore in subroutine get_eof_eor, usero' valori di default"
eof = -1
eor = -2
RETURN

END SUBROUTINE get_eof_eor

!$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

SUBROUTINE scrive_help
!
! Visualizza a schermo l'hlep del programma
!
IMPLICIT NONE
INTEGER :: mxstaz

!            12345678901234567890123456789012345678901234567890123456789012345678901234567890
WRITE (*,*) "proc_multi_orari.exe [-h] -o/-s/-sx/-q/-t filelst stat fileout [-ld]"
WRITE (*,*) "Legge un insieme di files relativi a serie storiche su punto"
WRITE (*,*) "Scrive un file con lo stesso formato, che per ogni data/parametro contiene"
WRITE (*,*) "  il risultato di una statistica sui files di input."
WRITE (*,*) 
WRITE (*,*) "filelst  : lista dei files da elaborare"
WRITE (*,*) "           -o  = formato estra_orari / estraqa orario"
WRITE (*,*) "           -s  = seriet"
WRITE (*,*) "           -sx = seriet con notazione esponenziale"
WRITE (*,*) "           -q  = estra_qaria giornaliero"
WRITE (*,*) "           -t  = trasp_temp"
WRITE (*,*) ""
WRITE (*,*) "stat     : elaborazione da compiere sui dati di input:"
WRITE (*,*) "           standard: ave, max, min, std, mdn"
WRITE (*,*) "           ""custom"": "
WRITE (*,*) "             tke: un solo file in input, passa da SQRT(2*TKE) a TKE"
WRITE (*,*) ""
WRITE (*,*) "fileout  : file di output"
WRITE (*,*) "-ld     : non controlla la corrispondenza dei livelli nei files di input"
WRITE (*,*) "          (utile per elaborare dati sui model layers COSMO)"
WRITE (*,*) "-h      : visualizza questo help"
WRITE (*,*) 

RETURN

END SUBROUTINE scrive_help


!$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
