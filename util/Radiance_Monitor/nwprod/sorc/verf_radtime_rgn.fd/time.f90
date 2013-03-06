program time
  use read_diag

  implicit none
  integer ntype
  parameter (ntype=8)

  character(10),dimension(ntype):: ftype
  character(8) stid
  character(20) satname,stringd,satsis
  character(10) dum,satype,dplat
  character(40) string,diag_rad,data_file,ctl_file,dfile
  character(10) suffix

  integer luname,lungrd,lunctl,lndiag
  integer iyy,imm,idd,ihh,idhh,incr,iread,iflag
  integer n_chan,j,idsat,i,k,ii,nreg
  integer,allocatable,dimension(:):: io_chan,nu_chan
  integer npred_radiag

  real rread,pen
  real weight,rlat,rlon,rmiss,obs,biascor,obsges,obsgesnbc,rterm
  real,dimension(2):: cor_tot,nbc_omg,bc_omg

  real,allocatable,dimension(:):: wavenumbr
  real,allocatable,dimension(:):: count,error,use,frequency,penalty
  real,allocatable,dimension(:,:):: tot_cor,omg_nbc,omg_bc


! Variables for reading satellite data
  type(diag_header_fix_list )         :: header_fix
  type(diag_header_chan_list),pointer :: header_chan(:)
  type(diag_data_name_list  )         :: data_name
  type(diag_data_fix_list   )         :: data_fix
  type(diag_data_chan_list  ),pointer :: data_chan(:)
  type(diag_data_extra_list ),pointer :: data_extra(:,:)

! Namelist with defaults
  logical               :: retrieval            = .false.
  integer               :: nchanl               = 19
  integer               :: imkctl               = 1
  integer               :: imkdata              = 1
  character(3)          :: gesanl               = 'ges'
  integer               :: little_endian        = 1
  namelist /input/ satname,iyy,imm,idd,ihh,idhh,incr,&
       nchanl,suffix,imkctl,imkdata,retrieval,gesanl,little_endian

  data luname,lungrd,lunctl,lndiag / 5, 51, 52, 21 /
  data rmiss /-999./
  data stringd / '.%y4%m2%d2%h2' /
  data ftype / 'count', 'penalty', &
       'omgnbc', 'total', 'omgbc', &
       'omgnbc2', 'total2', 'omgbc2' /



!************************************************************************
!
! Initialize variables
  iread=0
  npred_radiag = 5

! Read namelist input
  read(luname,input)
  write(6,input)
  write(6,*)' '
  write(6,*)'gesanl  = ', gesanl
  write(6,*)'suffix = ', suffix

  if ( trim(gesanl) == 'anl' ) then
     ftype(3) = 'omanbc'
     ftype(5) = 'omabc'
     ftype(6) = 'omanbc2'
     ftype(8) = 'omabc2'
  endif



! Create filenames for diagnostic input, GrADS output, and GrADS control files    
  write(stringd,100) iyy,imm,idd,ihh
100 format('.',i4.4,3i2.2)

  if ( trim(gesanl) == 'ges' ) then
     diag_rad = trim(satname)
     data_file= trim(satname) // trim(stringd) // '.ieee_d'
     ctl_file = trim(satname) // '.ctl'
  else
     diag_rad = trim(satname) // '_anl'
     data_file= trim(satname) // '_anl' // trim(stringd) // '.ieee_d'
     ctl_file = trim(satname) // '_anl.ctl'
  endif

  write(6,*)'diag_rad =',diag_rad
  write(6,*)'data_file=',data_file
  write(6,*)'ctl_file =',ctl_file


! Open unit to diagnostic file.  Read portion of header to 
! see if file exists
  open(lndiag,file=diag_rad,form='unformatted')
  read(lndiag,err=900,end=900) dum
  rewind lndiag

! File exists.  Read header
  write(6,*)'call read_diag_header'
  call read_radiag_header( lndiag, npred_radiag, retrieval, header_fix,&
        header_chan, data_name, iflag )
  if( iflag/=0 ) then
     write(6,*)'***ERROR*** problem reading diag file header, iflag=',iflag
     call errexit(91)
  endif

! Extract observation type, satellite id, and number of channels
  satype = header_fix%obstype
  satsis = header_fix%isis
  dplat  = header_fix%id
  n_chan = header_fix%nchan

  write(6,*)'satype,dplat,n_chan=',satype,' ',dplat,n_chan

  string = trim(satype)//'_'//trim(dplat)
  write(6,*)'string,satname=',string,' ',satname
  if ( trim(string) /= trim(satname) ) then
     write(6,*)'***ERROR*** inconsistent instrument types'
     write(6,*)'  satname,string  =',satname,' ',string
     call errexit(92)
  endif


! Allocate arrays to hold observational information
  write(6,*)' '
  write(6,*)'allocate arrays'
  allocate (io_chan(n_chan), nu_chan(n_chan), wavenumbr(n_chan))
  allocate (tot_cor(n_chan,2), omg_nbc(n_chan,2), &
       omg_bc(n_chan,2), count(n_chan), & 
       penalty(n_chan), &
       error(n_chan), use(n_chan), &
       frequency(n_chan))

! Zero accumulator arrays
  do ii=1,2
        do j=1,n_chan
           if (ii==1) then
              count(j) = 0.0
              penalty(j) = 0.0
           endif
           tot_cor(j,ii) = 0.0
           omg_nbc(j,ii) = 0.0
           omg_bc(j,ii)  = 0.0
        end do
  end do


! Extract satinfo relative index
  do j=1,n_chan
     nu_chan(j)   = real( header_chan(j)%nuchan, 4 )
     io_chan(j)   = real( header_chan(j)%iochan, 4 )
     wavenumbr(j) = real( header_chan(j)%wave, 4 )
  end do
     do j=1,n_chan
        error(j)     = real( header_chan(j)%varch, 4)
        use(j)       = real( header_chan(j)%iuse, 4 )
        frequency(j) = real( header_chan(j)%freq, 4)
     end do

! Create control file
  if ( imkctl == 1 ) then        
     write(6,*)'call create_ctl_time'

     if ( trim(gesanl) == 'ges' ) then
        dfile = trim(satname)
     else
        dfile = trim(satname) // '_anl'
     endif

     call create_ctl_time(ntype,ftype,n_chan,iyy,imm,idd,ihh,idhh,&
          incr,ctl_file,lunctl,rmiss,dfile,satype,dplat,1,&
          nu_chan,use,error,frequency,wavenumbr,little_endian)
  endif 

! Loop to read entries in diagnostic file
  iflag = 0
  loopd:  do while (iflag == 0)

!    Read a record.  If read flag, iflag does not equal zero, exit loopd
     call read_radiag_data( lndiag, header_fix, retrieval, data_fix, data_chan,&
           data_extra, iflag )
     if( iflag /= 0 ) exit loopd
     iread=iread+1

!    Extract observation location and mpi weight.  
!    Convert (0-360) lon to (-180,180)
     rlat   = data_fix%lat
     rlon   = data_fix%lon
     if (rlon>180.) rlon = rlon - 360.
     rread  = rread +1.0 

!    Channel loop
     do j = 1, n_chan

!       If observation was assimilated, accumulate sums in appropriate regions
        if (data_chan(j)%errinv > 1.e-6) then
           pen        =  data_chan(j)%errinv*(data_chan(j)%omgbc)**2
           cor_tot(1) =  (data_chan(j)%omgnbc - data_chan(j)%omgbc)
           nbc_omg(1) =  data_chan(j)%omgnbc
           bc_omg(1)  =  data_chan(j)%omgbc

           cor_tot(2) =  (data_chan(j)%omgnbc - data_chan(j)%omgbc)**2
           nbc_omg(2) =  (data_chan(j)%omgnbc)**2
           bc_omg(2)  =  (data_chan(j)%omgbc)**2
           
              count(j)   = count(j) + 1.0 
              penalty(j) = penalty(j) + pen
              do ii=1,2
                 tot_cor(j,ii) = tot_cor(j,ii) + cor_tot(ii)
                 omg_nbc(j,ii) = omg_nbc(j,ii) + nbc_omg(ii)
                 omg_bc(j,ii)  = omg_bc(j,ii)  + bc_omg(ii)
              end do
        endif

     enddo ! channel loop

! End of loop over diagnostic file
  enddo loopd
  close(lndiag)
  write(6,*)' '
  write(6,*)'read in ',iread,' obs ',rread
  write(6,*)' '

! Compute average and standard deviation
     do j=1,n_chan
        if (count(j)==0) then
!           write(6,*) 'penalty=',penalty(j),count(j)
!           penalty(j)=penalty(j)/count(j)
!            write(6,*) 'penalty=',penalty(j)
           count(j)=rmiss
           penalty(j)=rmiss
        endif
     end do


! Write output to binary data file
  if ( imkdata == 1 ) then        
     write(6,*)' '
     open(lungrd,file=data_file,form='unformatted')
     write(lungrd) (count(j),j=1,n_chan)
     write(lungrd) (penalty(j),j=1,n_chan)
     do ii=1,2
        write(lungrd) (omg_nbc(j,ii),j=1,n_chan)
        write(lungrd) (tot_cor(j,ii),j=1,n_chan)
        write(lungrd) (omg_bc (j,ii),j=1,n_chan)
     end do
     write(6,*)'write output to lungrd=',lungrd,', file=',trim(data_file)
     close(lungrd)
  endif

! Deallocate arrays
  write(6,*)' '
  write(6,*)'deallocate arrays'
  deallocate(io_chan,nu_chan,wavenumbr,tot_cor,omg_nbc,omg_bc,count,&
       penalty,error,use,frequency)
  goto 950

! Jump to here if eof or error reading diagnostic file.
900 continue
  write(6,*)'***PROBLEM reading diagnostic file.  diag_rad=',diag_rad
  close(lndiag)

  n_chan=nchanl
  if (n_chan<=0) then
     write(6,*)'***ERROR*** invalid nchanl=',nchanl,'  STOP program'
     call errexit(93)
  endif
     
  write(6,*)'load missing value ',rmiss,' into output arrays.  ',&
       n_chan
  allocate(count(n_chan),penalty(n_chan),&
       omg_nbc(n_chan,2),tot_cor(n_chan,2),&
       omg_bc(n_chan,2))
  do ii=1,2
        do j=1,n_chan
           if (ii==1) then
              count(j)  = rmiss
              penalty(j)= rmiss
           endif
           omg_nbc(j,ii) = rmiss
           tot_cor(j,ii) = rmiss
           omg_bc(j,ii)  = rmiss
        end do
  end do

  if ( imkdata == 1 ) then        
     open(lungrd,file=data_file,form='unformatted')
     write(lungrd) (count(j),j=1,n_chan)
     write(lungrd) (penalty(j),j=1,n_chan)
     do ii=1,2
        write(lungrd) (omg_nbc(j,ii),j=1,n_chan)
        write(lungrd) (tot_cor(j,ii),j=1,n_chan)
        write(lungrd) (omg_bc (j,ii),j=1,n_chan)
     end do
     write(6,*)'write output to lungrd=',lungrd,', file=',trim(data_file)
     close(lungrd)
  endif
  deallocate(count,penalty,omg_nbc,tot_cor,omg_bc)

! End of program
950 continue
  stop
end program time
