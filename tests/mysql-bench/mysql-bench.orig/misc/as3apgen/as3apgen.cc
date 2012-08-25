#include <stdio.h>
#include <math.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <getopt.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/times.h>
#include <unistd.h>


#ifdef DEBUG 
#      define DBG(body) { body; }
#else
#      define DBG(body)
#endif

#include "as3apgen.h"

/* DEFAULT Database size im MB */
int srows = 0;
/* DEFAULT action - no generate database */
int generate = 0;
/* DEFAULT no osdb compatable */
int osdb = 0;
/* DEFAULT put result files in current directory */
char path[2048];
/* Buffer for full path */
char full_path[3000];
/* Errors */
int err=0;

/* For measuring operations */

struct timeval start_time, start_table;
	

struct option long_options[] =
{
  {"size", 1, 0, 's'},
  {"path", 1, 0, 'p'},
  {"help", 0, 0, '?'},
  {0,0,0,0}     
};

void get_time(struct timeval begin)
{
    struct timeval end;

    gettimeofday(&end, NULL);             
    
    printf("Time %.02f\n",(end.tv_sec  - begin.tv_sec) +  1.0e-6*(end.tv_usec - begin.tv_usec));
}


enum
{
  uniques = 0, tenpct = 1, hundred = 2, updates = 3, tiny = 4
};


class Table
{
  protected:
    enum 
    { 
      col_key = 0, col_int = 1, col_signed = 2, col_float = 3, 
      col_double = 4, col_decimal = 5, col_date = 6, col_code = 7, 
      col_name = 8 , col_address = 9
    };

    char * tbl_name;
    int tbl_rows;
    int tbl_nfields;
    Column * tbl[10];
  
  public:
    Table(char * tname, int trows);
    ~Table();
    int print_table();
};

Table::Table(char * tname, int trows)
{
  tbl_nfields = 10;
  tbl_rows = trows;    

  tbl_name = new char[strlen(tname) + 1];
  strncpy(tbl_name, tname, strlen(tname));
  
  if (!strcmp(tbl_name,"uniques"))
  {
    tbl[col_key] = new Uniform_Column(trows,0,1000000000,trows,1);
    tbl[col_int] = new Uniform_Column(trows,0,1000000000,trows,1);
    tbl[col_signed] = new Uniform_Column(trows,-500000000,500000000,trows,0);
    tbl[col_float] = new Zipfian_Column(trows,-500000000,500000000,10);
    tbl[col_double] = new Normal_Column(trows,-1000000000,1000000000,trows);
    tbl[col_decimal] = new Uniform_Column(trows,-1000000000,1000000000,trows,0);
    tbl[col_date] = new Date_Column(trows,"1/1/1900","1/1/2000");
    tbl[col_code] = new Alphanum_Column(trows,10,trows);
    tbl[col_name] = new Alphanum_Column(trows,20,trows);
    tbl[col_address] = new Address_Column(trows,trows);
  }
  else 
    if(!strcmp(tbl_name,"updates"))
    {
      tbl[col_key] = new Uniform_Column(trows,0,trows,trows,1);
      tbl[col_int] = new Uniform_Column(trows,0,trows,trows,1);
      tbl[col_signed] = new Uniform_Column(trows,-500000000,500000000,trows,0);
      tbl[col_float] = new Zipfian_Column(trows,-500000000,500000000,10);
      tbl[col_double] = new Normal_Column(trows,-1000000000,1000000000,trows);
      tbl[col_decimal] = new Uniform_Column(trows,-1000000000,1000000000,trows,0);
      tbl[col_date] = new Date_Column(trows,"1/1/1900","1/1/2000");
      tbl[col_code] = new Alphanum_Column(trows,10,trows);
      tbl[col_name] = new Alphanum_Column(trows,20,trows);
      tbl[col_address] = new Address_Column(trows,trows);
    }
    else 
      if(!strcmp(tbl_name,"tenpct"))
      {
	  tbl[col_key] = new Uniform_Column(trows,0,1000000000,trows,1);
	  tbl[col_int] = new Uniform_Column(trows,0,1000000000,trows,1);
	  tbl[col_signed] = new Uniform_Column(trows,-500000000,500000000,trows,0);
	  tbl[col_float] = new Uniform_Column(trows,-500000000,500000000,trows/10,0);
	  tbl[col_double] = new Uniform_Column(trows,-1000000000,1000000000,trows/10,0);
	  tbl[col_decimal] = new Uniform_Column(trows,-1000000000,1000000000,trows/10,0);
	  tbl[col_date] = new Date_Column(trows,"1/1/1900","1/1/2000");
	  tbl[col_code] = new Alphanum_Column(trows,10,trows);
	  tbl[col_name] = new Alphanum_Column(trows,20,trows/10);
	  tbl[col_address] = new Address_Column(trows,trows/10);
      }
      else 
	if (!strcmp(tbl_name,"hundred"))
	{
	  tbl[col_key] = new Uniform_Column(trows,0,trows,trows,1);
	  tbl[col_int] = new Uniform_Column(trows,0,1000000000,trows,1);
	  tbl[col_signed] = new Sighundred_Column(trows,100,199,trows);
	  tbl[col_float] = new Uniform_Column(trows,-500000000,500000000,100,0);
	  tbl[col_double] = new Uniform_Column(trows,-1000000000,1000000000,100,0);
	  tbl[col_decimal] = new Uniform_Column(trows,-1000000000,1000000000,100,0);
	  tbl[col_date] = new Date_Column(trows,"1/1/1900","1/1/2000");
	  tbl[col_code] = new Alphanum_Column(trows,10,trows);
	  tbl[col_name] = new Alphanum_Column(trows,20,100);
	  tbl[col_address] = new Address_Column(trows,100);
	}
	else
	  if (!strcmp(tbl_name,"tiny"))
	  {
	    tbl[col_key] = new Uniform_Column(trows,0,trows,trows,1);
	    tbl_nfields = 1;
	  }
}

Table::~Table()
{
  delete [] tbl_name;
  for(int i=0; i<tbl_nfields;i++)
  {
    delete tbl[i];
  }
}

int Table::print_table(){
  
  char * value;
  char * delimiter;
  FILE * out;
  char * filename;
  int    rc; 
  
  filename = new char[30];

  if(osdb)
  {
    snprintf(filename,strlen(tbl_name)+6,"asap.%s",tbl_name);
  }
  else
  {
    snprintf(filename,strlen(tbl_name)+1,"%s",tbl_name);
  }

  if (strlen(path)) 
    snprintf(full_path,strlen(path)+1+strlen(filename)+1,"%s/%s",path,filename);
  else
    snprintf(full_path,strlen(filename)+1,"%s",filename);    

  fprintf(stdout,"Generating Table - %8s : ",tbl_name);

  out = fopen(full_path,"w");

  if (out != NULL)
  {
      for (int i=0; i<tbl_rows; i++)
      {
	  delimiter = "";
	  for (int j=0; j<tbl_nfields; j++)
	  {
	      value = tbl[j]->get_next_value();
	      fprintf(out, "%s%s", delimiter, value);
	      delimiter = ",";
	  }
	  fprintf(out,"\n");
      }
      printf("%d rows done. ",tbl_rows);
      rc=0;
      fclose(out);
  }
  else
  {
    fprintf(stdout,"Can not write to output file %s\n",full_path);
    rc=-1;
  }
  delete [] filename;
  return rc;
}

void usage(int exitcode)
{
  fprintf(stderr, "Tool for generation tables for as3ap benchmark, %s, MySQL AB, 2002-2003\n", AS3APGEN_VERSION);
  fprintf(stderr, "Usage: as3apgen [options]\n");
  fprintf(stderr, "-?, --help - this message\n");
  fprintf(stderr, "-s, --size=[4|40|400|4000|40000|400000] - size of dataset in Mb\n");
  fprintf(stderr, "-p, --path=\"path where generated files should be placed\"\n");
  fprintf(stderr, "-o, --osdb - osdb compatable filename format\n");
  exit(exitcode);
}

void parse_args(int argc, char** argv)
{
  int c, opt_ind = 0;
  struct stat statBuf;
  
  while((c = getopt_long(argc, argv,"?op:s:", long_options,
			 &opt_ind)) != EOF)
  {
    switch(c)
    {
      case '?': usage(0);
      case 'o': osdb = 1; break;
      case 'p': 
	       if (strlen(optarg)<2048)
	       {
		 snprintf(path,strlen(optarg)+1,"%s",optarg); 
		 break;
	       }
	       else 
	       {
		 fprintf(stdout, "Path should be less than 2048 symbols\n");
		 usage(0);
	       }
     case 's': srows = atoi(optarg); break;
     default: usage(1); 
    }
  }
  
  if (strlen(path))
  {
    if ((path[0] == '.') || (path[0] == '~')) 
    {
      fprintf(stdout, "must specify absolute path for --path\n\n");
      usage(1);
    }
    if (stat(path, &statBuf))
    {
      fprintf(stdout, "Path %s not exists or access denied\n\n",path);
      usage(1);
    }
  }
  
  if (srows == 4 || srows == 40 || srows == 400 || srows == 4000 || 
      srows == 40000 || srows == 400000)
  {
    srows *= 2500;
    generate= 1;
  }
  else
  {
    fprintf(stdout, "WARNING: Wrong size %d. Please see usage below.\n\n",srows);
    usage(0);
  }
}


int main(int argc, char **argv) {

  /* Turn off bufferization on stdout */
  setvbuf(stdout, NULL, _IONBF, 0);
  fprintf(stdout,"\n");
  
  if (argc > 1)
  {
    parse_args(argc, argv);
    
    if (generate)
    {
      if(strlen(path))
      {
	 fprintf(stdout,"WARNING: Old dataset in directory %s will be rewrited\n\n", path);
      }
      else
      {
	 fprintf(stdout,"WARNING: Old dataset in current directory will be rewrited\n\n");
      }
      fprintf(stdout,"Starting to generate dataset. Logical size of dataset is %dMb\n",(int)(srows*4.0/10000)); 
      
      printf("Initialization : ");
      gettimeofday(&start_time, NULL);
      Table * t[5] = { new Table("uniques",srows),
		       new Table("updates",srows),
		       new Table("hundred",srows),                     
		       new Table("tenpct",srows),                     
		       new Table("tiny",1) 
		     };
      
      printf("Done ");
      get_time(start_time);                                     
      
      gettimeofday(&start_time, NULL);
      
      for (int i=0; i<5; i++)
      {
	gettimeofday(&start_table, NULL);

	if (!t[i]->print_table())
	  err++;

	delete t[i];
	get_time(start_table);
      }
      
      fprintf(stdout,"Done. ");
      get_time(start_time);          
    }
    if (!err)
      exit(1);
  }
  else
  {
    usage(0);
  }
}

