
class Column{
  
 protected:
  int rows;
  int width;
  char *  tmp;  
  
 public:
  Column(int nrows, int width)
  { 
    rows = nrows;
    
    /* Buffer, for convert from Type(Double,Date,Int,...) -> String  */
    tmp = new char[width];
  }
  virtual char * get_next_value() = 0;
  virtual inline ~Column(){ delete [] tmp;}
};

/*
 Uniform distributed value
*/

class Uniform_Column : public Column{
  
 protected:
  int start;
  int end;
  int uniques;
  int skip1;
  int index;
  double value;
  long long resvalue;
  int range;
  double step;
  int count;
  int uniq_count;
  int uniq_count_repeat;

  int Root[18];
  long long Prime[18];
  long long P, seed;
  int G;
  
 public:
  Uniform_Column(int Nrows, int Nstart, int Nend, int Nuniques, 
		 int Nskip1);
  virtual char * get_next_value();
  inline ~Uniform_Column(){}

  private:
    long long next_value();
};

Uniform_Column::Uniform_Column(int Nrows, int Nstart, int Nend, int Nuniques, 
		      int Nskip1) : Column(Nrows, 20)
{

  int Root[18] = { 2, 7, 26, 59, 242, 568, 1792,
		   5649, 16807, 30001, 60010, 180001, 360002,
		   1000001, 2000000, 60000008, 120000000, 360000004};

  long long Prime[18] = {11, 101, 1009, 10007, 100003, 1000003, 10000019,
			 100000007, 2147483647, 10000000019ll, 100000000003ll, 
			 1000000000039ll, 10000000000037ll, 100000000000031ll, 
			 1000000000000037ll, 10000000000000061ll, 
			 100000000000000003ll,1000000000000000003ll};

  start = Nstart;
  end = Nend;
  uniques = Nuniques;
  skip1 = Nskip1;
  index=0;
  step = 1.0;
  
  range = end - start;
  
  if (rows != range)
  {
    if (uniques <= range)
    {
      step = (double)range / (uniques - 1);
    }
    else
    {
      step = (double)(rows - 1) / uniques;
    }
  }

  count = (int) (1.0 * rows / uniques);
 
  if (uniques != 1)
  {
    index= (int)(log10(uniques))-1;
  }

  G = Root[index];
  P = Prime[index];

  seed = G;
  uniq_count = 0;
  uniq_count_repeat = 0;
  value = start + next_value() * step;
  
}

long long Uniform_Column::next_value()
{
   seed = (G * seed) % P;
   while ( seed > uniques ) 
	  seed = (G * seed) % P;
   return seed - 1;
}

char * Uniform_Column::get_next_value()
{
    
  if (uniq_count < uniques)
  {
    if (uniq_count_repeat < count)
    {
      uniq_count_repeat++;
    }
    else
    {
      uniq_count_repeat = 1;
      uniq_count++;
      value = start + next_value() * step;
    }
	
    if (skip1 && llrint(value)==1)
    {
      value = end;
    }
    resvalue =  llrint(value);
  }
  snprintf(tmp, 20, "%lld",resvalue);

  return  tmp;
}                

class Sighundred_Column : public Column
{

 protected:
  int start;
  int end;
  int uniques;
  int skip1;
  
  double value;
  long long resvalue;
  int range;
  double step;
  long long P,seed;
  int G;
  int count;
  int uniq_count;
  int uniq_count_repeat;
  
 public:
  Sighundred_Column(int Nrows, int Nstart, int Nend, int Nuniques);
  virtual char * get_next_value();
  inline ~Sighundred_Column(){}
 private:
  long long next_value();
};

Sighundred_Column::Sighundred_Column(int Nrows, int Nstart, int Nend,
			  int Nuniques) : Column(Nrows, 20)
{
  start = Nstart;
  end = Nend;
  uniques = Nuniques;

  range = end - start + 1;
  count = (int) (1.0 * rows / range );

  G = 7;
  P = 101;

  seed = G;

  value = 100 + next_value();
  
  uniq_count = 0;
  uniq_count_repeat = 0;
}

long long Sighundred_Column::next_value()
{
   seed = (G * seed) % P;
   while ( seed > 100 ) seed = (G * seed) % P;
   return seed-1;
}


char * Sighundred_Column::get_next_value()
{

  if (uniq_count < uniques)
  {
    if (uniq_count_repeat<count)
    {
      uniq_count_repeat++;
    }
    else
    {
      uniq_count_repeat = 1;
      uniq_count++;
      value = 100 + next_value();
    }
    resvalue = llrint(value);
  }
  snprintf(tmp, 20, "%lld",resvalue);
  return  tmp;
}                

class Zipfian_Column : public Column
{

 protected:
  int start;
  int end;
  int uniques;
  
  double zipf_k;
  
  double value;
  int range;
  double step;
  int count;
  int uniq_count;
  int uniq_count_repeat;
  
  int z_table[10];
  int sum;
  
 public:
  Zipfian_Column(int Nrows, int Nstart, int Nend, int Nuniques);
  virtual char * get_next_value();
  inline ~Zipfian_Column(){}
};

Zipfian_Column::Zipfian_Column(int Nrows, int Nstart, int Nend, int Nuniques) : 
		      Column(Nrows, 20)
{
  start = Nstart;
  end = Nend;
  uniques = Nuniques;

  value = (double) start;
  range = end - start;
  
  zipf_k = 0.645257982786419;
  
  step = (double)range / uniques;
  count = (rows / uniques);
  sum = 0;

  uniq_count = 0;
  uniq_count_repeat = 0;
  
  for(int i=0;i<10;i++)
  {
    double zpdf=zipf_k / ((i + 1) * (i + 1));
    z_table[i] = (int) (zpdf*rows);
    sum += z_table[i];
  }
  int diff = rows - sum;

  if (diff != 0)
  {
    if (diff < 0)
    {
      z_table[0] -= diff;
    }
    else
    {
      z_table[0] += diff;
    }
  }
  sum = 0;
}

char * Zipfian_Column::get_next_value()
{

  if ( uniq_count < uniques)
  {
    count = z_table[uniq_count];
    
    if ( uniq_count_repeat<count)
    {
      uniq_count_repeat++;
    }
    else
    {
      uniq_count++;
      sum += uniq_count_repeat;
      value += step;
      uniq_count_repeat = 1;
    }
  }
  snprintf(tmp, 20, "%f",value);
  return  tmp;

}                

class Normal_Column : public Column
{

 protected:
  int start;
  int end;
  int uniques;
  
  double sigma;
  
  double value;
  int range;
  double step;
  int count;
  int uniq_count;
  int uniq_count_repeat;
  
 public:
  Normal_Column(int Nrows, int Nstart, int Nend, int Nuniques);
  virtual char * get_next_value();
  inline ~Normal_Column(){}

 private:
  double Uniform_2_Normal();
};

Normal_Column::Normal_Column(int Nrows, int Nstart, int Nend, int Nuniques) 
			: Column(Nrows, 20)
{
  start = Nstart;
  end = Nend;
  uniques = Nuniques;
  
  value = 0;
  range = end - start;
  
  count = (rows/uniques);
  sigma = end / 3.0;
  
  uniq_count = 0;
  uniq_count_repeat = 0;
}

char * Normal_Column::get_next_value()
{

  if ( uniq_count < uniques)
  {
    if ( uniq_count_repeat<count)
    {
      uniq_count_repeat++;
    }
    else
    {
      while(1)
      {
	value = sigma * Uniform_2_Normal();
	if ( fabs(value) <= end ) { break; }
      }
      uniq_count++;
      uniq_count_repeat = 1;
    }
  }
  snprintf(tmp, 20, "%f",value);
  return  tmp;

}                

double Normal_Column::Uniform_2_Normal()
{

  int n = 12;
  double tmp, sum_n = 0;
  
  for ( int i=0; i<n; i++)
  {
    sum_n += (double) (1.0 * rand())/(RAND_MAX + 1.0);
  }
  tmp = (double) ((sum_n - (n / 2.0)) / sqrt (n / 12.0));
  return tmp;
}

class Date_Column : public Column
{
  
 protected:
  int start;
  int end;
  
  int range;
  
  double value;
  double step;

  int G;
  long long P,seed; 
  
 public:
  Date_Column(int Nrows, char * Nstart, char * Nend);
  int sum;                        
  virtual char * get_next_value();
  inline ~Date_Column(){}

 private:
  int From_Date(char * dtDate);
  char * To_Date(int number_of_day);
  long long next_value();
};

Date_Column::Date_Column(int Nrows, char * Nstart, char * Nend) : 
						    Column(Nrows,20)
{

  int Root[18] = { 2, 7, 26, 59, 242, 568, 1792,
		   5649, 16807, 30001, 60010, 180001, 360002,
		   1000001, 2000000, 60000008, 120000000, 360000004};

  long long Prime[18] = {11, 101, 1009, 10007, 100003, 1000003, 10000019,
			 100000007, 2147483647, 10000000019ll, 100000000003ll, 
			 1000000000039ll, 10000000000037ll, 100000000000031ll, 
			 1000000000000037ll, 10000000000000061ll, 
			 100000000000000003ll,1000000000000000003ll};

  start = From_Date(Nstart);
  end = From_Date(Nend);

  G = Root[(int)(log10(rows))-1];
  P = Prime[(int)(log10(rows))-1];

  seed = G;

  range = end - start;

  step = (double)range / rows;

}

long long Date_Column::next_value()
{
   seed = (G * seed) % P;
   while ( seed > rows ) seed = (G * seed) % P;
   return seed - 1;
}


char * Date_Column::get_next_value()
{
  return To_Date(start + (int) (next_value() * step));
}                

int Date_Column::From_Date(char * dtDate)
{

  char * tmp2;
  char * token;
  int tmp_arr[3];
  
  tmp2 = tmp;
  strncpy(tmp, dtDate, strlen(dtDate) + 1);
  
  int num_tokens = 0;
  
  while ((token = strsep(&tmp, "/")) && num_tokens < 3 ){
    tmp_arr[num_tokens] = (int) strtol(token, (char **)NULL, 10);
    if (errno != ERANGE)
    {
	 num_tokens++;
    }
  }
  if (num_tokens != 3 )
  {
    // Something wrong
    return 0;
  }
  int day = tmp_arr[0];
  int month = tmp_arr[1];
  int year = tmp_arr[2];
  
  int julian_day = (int) (( 1461 * ( year + 4800 + (int) (( month - 14 ) / 12.) ) ) / 4.) +
    (int) (( 367 * ( month - 2 - 12 * int (( month - 14 ) / 12. ) ) ) / 12.) -
    (int)(( 3 * (int)( ( year + 4900 + (int)(( month - 14 ) / 12. )) / 100. ) ) / 4.) +
    day - 32075;

  tmp = tmp2;
  return julian_day;
			    
}

char * Date_Column::To_Date(int number_of_day)
{
     
  int l = number_of_day + 68569;
  int n = (int) (( 4 * l ) / 146097.);
  l = l - (int) (( 146097 * n + 3 ) / 4.);
  int i = (int)(( 4000 * ( l + 1 ) ) / 1461001.);
  l = l - (int)(( 1461 * i ) / 4.) + 31;
  int j = (int)(( 80 * l ) / 2447.);
  int d = l - (int)(( 2447 * j ) / 80.);
  l = (int)(j / 11);
  int m = j + 2 - ( 12 * l );
  int y = 100 * ( n - 49 ) + i + l;
  
  snprintf(tmp, 15, "\'%.4d-%.2d-%.2d\'", y, m, d);
  return tmp;
}

class Alphanum_Column : public Column
{
  
 protected:
  int len;
  int uniques;
  
  char * table;
  char * value;
  
  int count;
  int flag;
  int tablelen;

  int uniq_count;
  int uniq_count_repeat;
  
public:
  Alphanum_Column(int Nrows, int Nlen, int Nuniques);
  inline ~Alphanum_Column(){ delete [] value;}
  virtual char * get_next_value();
  
private:
 int get_char(int str_len);
};

Alphanum_Column::Alphanum_Column(int Nrows, int Nlen, int Nuniques) : 
			 Column(Nrows, 30)
{
  len = Nlen;
  uniques = Nuniques;
  
  flag = 0;
  value = new char[len+1];
  
  if (len == 10) 
  {
    strncpy(value,"BENCHMARKS\0",len+1);
    flag = 1;
  }
  else 
    if(len == 20)
    {
      strncpy(value,"THE+ASAP+BENCHMARKS+\0",len+1);
      flag = 1;
    }

  count = (int) (rows/uniques);

  table = "0123456789zxcvbnmlkjhgfdsaqwertyuiopZXCVBNMLKJHGFDSAQWERTYUIOP";
  tablelen = strlen(table);
  
  uniq_count= 0;
  uniq_count_repeat= 0;
}

char * Alphanum_Column::get_next_value()
{
  
  if (uniq_count < uniques)
  {
    if (uniq_count_repeat<count && !flag && strlen(value))
    {
      uniq_count_repeat++;
    }
    else
    {
      if (flag)
      {
	flag = 0;
      }
      else
      {
	for (int i=0; i<len; i++)
	{
	  tmp[i] = table[get_char(tablelen)];
	}
	strncpy(value, tmp, len);
      }

      uniq_count_repeat = 1;
      uniq_count++;
    }
  }
  snprintf(tmp, len+3, "\'%s\'", value);
  return  tmp;
}                

inline int  Alphanum_Column::get_char(int str_len)
{
      return (int) (str_len * 1.0 * rand() / (RAND_MAX + 1.0));
}

class Address_Column : public Column{

protected:
  
  int uniques;
  int value;
  int count;
  int item_index;
  int item_cnt;
  int uniq_count;
  int uniq_count_repeat;
  
  long items[80];
  long * index[80];
  int predefine;
 
  char * str_table;
  int str_table_len;

public:
  Address_Column(int Nrows, int Nuniques);
  inline ~Address_Column()
	  { 
	  }
  virtual char * get_next_value();
  
private:
  static int sort_by_value(const void *x, const void *y);
  int rnd_value (const int min, const int max);
  double uniform2normal();
  void init_table(long items[], long * index[], const int maxn);
  void show_init_table(const int maxn, const char * name);
  void lognormal(const int uniq, int &resx, int &pdfx);
  char * get_string(int len, int num);
  void get_string2(int len, int num);

  void get_predefine();
};

void Address_Column::get_predefine()
{

  int ind=0;
  int min=10000;
  
  while (*(index[ind])>0)
  {
    if( abs((index[ind] - items) - 13) < abs(13 - min) )
    { 
      min = index[ind] - items;
    }
    ind++;
  }

  if (min>0  && min<80){
    items[min]--;
  }
  else
  {
    //Something wrong with choosing number for replace
    (*(index[0]))--;
  }
  items[13]++;
  DBG(show_init_table( 80, "predefine"));
}

Address_Column::Address_Column(int Nrows, int Nuniques) : Column(Nrows, 85)
{
  
  uniques = Nuniques;
  count = (int) (rows/uniques);
  
  for(int p=0; p<80; p++){
    items[p] = 0;
    index[p] = &items[p];
  }
  
  init_table(items, index, 80);

  if (items[13] == 0) get_predefine();

  predefine = 0;
  item_index = 0;
  item_cnt = 0;
  uniq_count = 0;
  uniq_count_repeat = 0;

  str_table = "0123456789zxcvbnmlkjhgfdsaqwertyuiopZXCVBNMLKJHGFDSAQWERTYUIOP";
  str_table_len = strlen(str_table);

  value = index[item_index] - items;
}

char * Address_Column::get_next_value()
{
  
  if (uniq_count < uniques)
  {
    if (uniq_count_repeat<count)
    {
      uniq_count_repeat++;
    }
    else
    {
      uniq_count_repeat = 1;
      uniq_count++;
      
      if (item_cnt < *(index[item_index]))
      {
	item_cnt++;
	predefine=0;
      }
      else
      {
	item_cnt= 0;
	item_index++;
	value = index[item_index] - items;
	if (value == 13)
	{
	  predefine= 1;
	}
      }
    }

    if (!predefine)
    {
      get_string2(value + 1,  item_cnt);
    }else{
      snprintf(tmp, 17, "\'SILICON VALLEY\'\0");
    }

    return  tmp;

  }else{ 
    printf("ERROR!\n");
  }
}                

char * Address_Column::get_string(int len, int num)
{
  
  char * arr = "0123456789zxcvbnmlkjhgfdsaqwertyuiopZXCVBNMLKJHGFDSAQWERTYUIOP";
  int mod;
  int arrlen = strlen(arr);
  char * str;
  
  str = new char [len];

  for (int i=0; i<len; i++)
  {
    mod = num % arrlen;
    str[i] = arr[mod];
    num = (int) (1.0 * num / arrlen);

  }

  str[len] = '\0';
  DBG(printf("STR |%d|%s|\n",len,str));
  return str;
}

void Address_Column::get_string2(int len, int num)
{
  
  int mod;

  tmp[0]='\'';
  
  for (int i=0; i<len; i++)
  {
    mod = num % str_table_len;
    tmp[i+1] = str_table[mod];
    num = (int) (1.0 * num / str_table_len);    
  }
  
  tmp[len+1] = '\'';
  tmp[len+2] = '\0';
}


int Address_Column::rnd_value (const int min, const int max)
{
  return (int) (min + (max * 1.0 * rand()) / (RAND_MAX + 1.0));
}

int Address_Column::sort_by_value(const void *x, const void *y)
{
  if ( (*(long *)(*(long *)x)) < (*(long *)(*(long *)y)) ) return 1;
  else
    if ( (*(long *)(*(long *)x)) == (*(long *)(*(long *)y)) ) return 0;
    else
      return -1;
}

double Address_Column::uniform2normal()
{
  int n = 12;
  double s = 0;
  
  for(int i=0; i<n; i++)
  {
    s = s + (1.0 * rand()) / (RAND_MAX);
  }
  return (s - (n / 2.0)) / sqrt(n / 12.0);
}

void Address_Column::lognormal(const int uniq, int &resx, int &pdfx)
{

  double PI = 3.14159265358979323846264338327950288419716939937510;
  double m = 40.0;
  double sig = 1.25;
  
  int  koef;
  double rnd, x;
  
  if ( uniq <= 10000)
  {
    koef = 1000;
  }
  else
  {
    koef = uniq/10;
  }
  
  while(1)
  {
    rnd = uniform2normal();
    x =   m * exp(sig * rnd);
    if ( floor(x)>0 && floor(x)<81)
    {
	pdfx = (int) floor(koef * (1.0 / (x * sig * sqrt(2.0 * PI)) * 
				   (exp(-(log(x / m)*log(x / m))/(2.0* sig* sig)))));
	resx = (int) floor(x);
	break;
    }
  }
}

void Address_Column::show_init_table(const int maxn, const char * name)
{
  double s = 0;
  int c = 0;
  char * tmp;

  printf("------------------------ %s -----------------------\n",name);  
  for(int u=0;u <maxn; u++)
  {
		printf("ARR[%2d]=%5d || %2d - %5d||\n",u, items[u], index[u]-items, *(index[u]));
		c += items[u];
		s += (double)  items[u] * u;
  }
  printf("\n\nSUM %f COUNT %d\n",s,c);
}

/*
   items[] - each item consists of count of repetition of this item.
   index[] - array of pointers on items
	     We use this array for sorting array of items by value
   maxn    - max number of items 
*/

void Address_Column::init_table(long items[], long * index[], const int maxn)
{

  int left_step_to_go = uniques;
  double left_sum_to_go = 20.0 * uniques;
  
  int step_len, step_count, step_sum;
  int rnd, counter;
  int u;
  int low_back_limit = 30;

  DBG(printf("Start %d %d\n",left_sum_to_go, left_step_to_go));
  
  while(1)
  {
    //Get new String len and count
    while(1)
    {
      lognormal(uniques, step_len, step_count);
      
      if ( ( step_len == 1 && (items[0] + step_count)<30) || 
	   ( step_len == 2 && (items[1] + step_count)<1275) ||
	   ( step_len == 3 && (items[2] + step_count)<102050) || 
	   ( step_len == 4 && (items[3] + step_count)<17178876) || step_len>4)
      {
	break;
      }
    }
    
    step_sum = step_count * step_len;
    
    if ( step_sum * 1.0 >= left_sum_to_go)
    {
      if ( step_count >= left_step_to_go)
      {
	step_count = (int) left_step_to_go;
	step_sum = step_count * step_len;
	items[step_len - 1] += step_count;
	break;
      }
      else
      {
	/* Go back */
	qsort(index, 80, sizeof(long), sort_by_value);             

	counter = 0;
	for(int u = low_back_limit; u<maxn && counter<5; u++)
	{
	  if (items[index[u] - items] > 0)
	  {
	    rnd = rnd_value(0, items[index[u] - items]);

	    items[index[u] - items] -= rnd;

	    left_step_to_go += rnd;
	    left_sum_to_go += (double) (1.0 * rnd * (index[u] - items));
	    counter++;
	  }
	}
	if( !counter && low_back_limit>0)
	{
	    low_back_limit = low_back_limit - 5;
	}
      }
    }
    else 
      if ( step_count >= left_step_to_go)
      {
	if ( step_sum >= left_sum_to_go)
	{
	  step_count = (int) left_step_to_go;
	  step_sum = step_count* step_len;
	  items[step_len - 1] += step_count;
	  break;
	}
	else
	{
	  /* Deviation for length of path */
	  if (fabs(left_sum_to_go - left_step_to_go * step_len * 1.0)< uniques * 5.0)
	  {
	    step_count = (int) left_step_to_go;
	    step_sum = step_count * step_len;
	    items[step_len - 1] += step_count;
	    break;
	  }
	  else
	  {
	  /* Go back 2  */
	  qsort(index, 80,sizeof(long),sort_by_value);             

	  for(int u=0; u<40; u++)
	  {
	    if (items[index[u] - items] > 0)
	    {
	      rnd = rnd_value(0,items[index[u] - items]);
	      items[index[u] - items] -= rnd;
	      left_step_to_go += rnd;
	      left_sum_to_go += 1.0 * rnd * (index[u] - items);
	    }
	  }
	}
	}
      }
      else
      {
	left_sum_to_go -= step_sum * 1.0;
	left_step_to_go -= step_count;
	items[step_len-1] += step_count;
      }
  }
  qsort(index, 80,sizeof(long),sort_by_value);
  
  DBG(show_init_table( maxn, "finish"));
}
