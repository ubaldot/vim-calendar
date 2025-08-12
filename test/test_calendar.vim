vim9script

# Test for the calendar plugin.
# Some features are not tested, like CalendarT since it depends on the screen 
# resolution and the screen size. The same for the test 

import "./common.vim"
var WaitForAssert = common.WaitForAssert

packadd calendar

def g:Test_calendar_basic()

  Calendar 1998, 10
  WaitForAssert(() => assert_equal(2, winnr('$')))

  # Check the current layout should be something like: ['row', [['leaf', 1000], ['leaf', 1003]]]
  var expected_value = 'row'
  assert_equal(expected_value, winlayout()[0])
  var expected_value_nr = 2
  assert_equal(expected_value_nr, len(winlayout()))
  assert_equal(expected_value_nr, len(winlayout()[1]))

  # Check October 1998
  expected_value =<< END
   <Prev Today Next> 

     1998/9(Sep)      
 Su Mo Tu We Th Fr Sa 
        1  2  3  4  5 
  6  7  8  9 10 11 12 
 13 14 15 16 17 18 19 
 20 21 22 23 24 25 26 
 27 28 29 30          
 
     1998/10(Oct)     
 Su Mo Tu We Th Fr Sa 
              1  2  3 
  4  5  6  7  8  9 10 
 11 12 13 14 15 16 17 
 18 19 20 21 22 23 24 
 25 26 27 28 29 30 31 
 
     1998/11(Nov)     
 Su Mo Tu We Th Fr Sa 
  1  2  3  4  5  6  7 
  8  9 10 11 12 13 14 
 15 16 17 18 19 20 21 
 22 23 24 25 26 27 28 
 29 30                

END
  assert_equal(expected_value, getline(1, '$'))

  # Move to next page
  exe "norm \<right>"

  var expected_value_right =<< END
   <Prev Today Next> 

     1998/10(Oct)     
 Su Mo Tu We Th Fr Sa 
              1  2  3 
  4  5  6  7  8  9 10 
 11 12 13 14 15 16 17 
 18 19 20 21 22 23 24 
 25 26 27 28 29 30 31 
 
     1998/11(Nov)     
 Su Mo Tu We Th Fr Sa 
  1  2  3  4  5  6  7 
  8  9 10 11 12 13 14 
 15 16 17 18 19 20 21 
 22 23 24 25 26 27 28 
 29 30                
 
     1998/12(Dec)     
 Su Mo Tu We Th Fr Sa 
        1  2  3  4  5 
  6  7  8  9 10 11 12 
 13 14 15 16 17 18 19 
 20 21 22 23 24 25 26 
 27 28 29 30 31       

END
  assert_equal(expected_value_right, getline(1, '$'))

  # Move back to the previous page
  exe "norm \<left>"
  assert_equal(expected_value, getline(1, '$'))

  # Close calendar
  exe "norm q"
  assert_equal(1, winnr('$'))

  :%bw!
enddef

def g:Test_calendarH_basic()

  CalendarH 2020, 2
  WaitForAssert(() => assert_equal(2, winnr('$')))

  # Check the current layout should be something like: ['col', [['leaf', 1000], ['leaf', 1003]]]
  var expected_value = 'col'
  assert_equal(expected_value, winlayout()[0])
  var expected_value_nr = 2
  assert_equal(expected_value_nr, len(winlayout()))
  assert_equal(expected_value_nr, len(winlayout()[1]))

  # Check February 2020 (Covid time!)
  expected_value =<< END
                         <Prev Today Next> 

|     2020/1(Jan)      |     2020/2(Feb)      |     2020/3(Mar) 
| Su Mo Tu We Th Fr Sa | Su Mo Tu We Th Fr Sa | Su Mo Tu We Th Fr Sa 
|           1  2  3  4 |                    1 |  1  2  3  4  5  6  7 
|  5  6  7  8  9 10 11 |  2  3  4  5  6  7  8 |  8  9 10 11 12 13 14 
| 12 13 14 15 16 17 18 |  9 10 11 12 13 14 15 | 15 16 17 18 19 20 21 
| 19 20 21 22 23 24 25 | 16 17 18 19 20 21 22 | 22 23 24 25 26 27 28 
| 26 27 28 29 30 31    | 23 24 25 26 27 28 29 | 29 30 31             

END
  assert_equal(expected_value, getline(1, '$'))

  # Move to next page
  exe "norm \<right>"

  var expected_value_right =<< END
                         <Prev Today Next> 

|     2020/2(Feb)      |     2020/3(Mar)      |     2020/4(Apr) 
| Su Mo Tu We Th Fr Sa | Su Mo Tu We Th Fr Sa | Su Mo Tu We Th Fr Sa 
|                    1 |  1  2  3  4  5  6  7 |           1  2  3  4 
|  2  3  4  5  6  7  8 |  8  9 10 11 12 13 14 |  5  6  7  8  9 10 11 
|  9 10 11 12 13 14 15 | 15 16 17 18 19 20 21 | 12 13 14 15 16 17 18 
| 16 17 18 19 20 21 22 | 22 23 24 25 26 27 28 | 19 20 21 22 23 24 25 
| 23 24 25 26 27 28 29 | 29 30 31             | 26 27 28 29 30       

END
  assert_equal(expected_value_right, getline(1, '$'))

  # Move back to the previous page
  exe "norm \<left>"
  assert_equal(expected_value, getline(1, '$'))

  # Close calendar
  exe "norm q"
  assert_equal(1, winnr('$'))

  :%bw!
enddef

def g:Test_calendarVR_basic()
  # OBS: this test is identical to g:Test_calendar_basic()

  CalendarVR 1998, 10
  WaitForAssert(() => assert_equal(2, winnr('$')))

  # Check the current layout should be something like: ['row', [['leaf', 1000], ['leaf', 1003]]]
  var expected_value = 'row'
  assert_equal(expected_value, winlayout()[0])
  var expected_value_nr = 2
  assert_equal(expected_value_nr, len(winlayout()))
  assert_equal(expected_value_nr, len(winlayout()[1]))

  # Check October 1998
  expected_value =<< END
   <Prev Today Next> 

     1998/9(Sep)      
 Su Mo Tu We Th Fr Sa 
        1  2  3  4  5 
  6  7  8  9 10 11 12 
 13 14 15 16 17 18 19 
 20 21 22 23 24 25 26 
 27 28 29 30          
 
     1998/10(Oct)     
 Su Mo Tu We Th Fr Sa 
              1  2  3 
  4  5  6  7  8  9 10 
 11 12 13 14 15 16 17 
 18 19 20 21 22 23 24 
 25 26 27 28 29 30 31 
 
     1998/11(Nov)     
 Su Mo Tu We Th Fr Sa 
  1  2  3  4  5  6  7 
  8  9 10 11 12 13 14 
 15 16 17 18 19 20 21 
 22 23 24 25 26 27 28 
 29 30                

END
  assert_equal(expected_value, getline(1, '$'))

  # Move to next page
  exe "norm \<right>"

  var expected_value_right =<< END
   <Prev Today Next> 

     1998/10(Oct)     
 Su Mo Tu We Th Fr Sa 
              1  2  3 
  4  5  6  7  8  9 10 
 11 12 13 14 15 16 17 
 18 19 20 21 22 23 24 
 25 26 27 28 29 30 31 
 
     1998/11(Nov)     
 Su Mo Tu We Th Fr Sa 
  1  2  3  4  5  6  7 
  8  9 10 11 12 13 14 
 15 16 17 18 19 20 21 
 22 23 24 25 26 27 28 
 29 30                
 
     1998/12(Dec)     
 Su Mo Tu We Th Fr Sa 
        1  2  3  4  5 
  6  7  8  9 10 11 12 
 13 14 15 16 17 18 19 
 20 21 22 23 24 25 26 
 27 28 29 30 31       

END
  assert_equal(expected_value_right, getline(1, '$'))

  # Move back to the previous page
  exe "norm \<left>"
  assert_equal(expected_value, getline(1, '$'))

  # Close calendar
  exe "norm q"
  assert_equal(1, winnr('$'))

  :%bw!
enddef

# TODO: help in writing this test
# func g:Test_calendarSearch_basic()
#   " Create file
#   let year = strftime('%y')
#   let month = strftime('%m')
#   let day = strftime('%m')

#   let filename = $"~/diary/{year}/{month}/{day}.md"->fnamemodify(':p')

#   Calendar
#   call WaitForAssert({-> assert_equal(2, winnr('$'))})
#   exe "norm \<cr>"

#   norm! iFoo
#   exe "norm! :wq\<cr>"

#   :bw!
# endfunc

def g:Test_config()
  # test g:calendar_navi
  g:calendar_navi = 'both'
  g:calendar_navi_label = '<--, |, -->'

  Calendar
  WaitForAssert(() => assert_equal(2, winnr('$')))

  # Check the current layout should be something like: ['row', [['leaf', 1000], ['leaf', 1003]]]
  var expected_value = 'row'
  assert_equal(expected_value, winlayout()[0])
  var expected_value_nr = 2
  assert_equal(expected_value_nr, len(winlayout()))
  assert_equal(expected_value_nr, len(winlayout()[1]))

  # Check label both on top and in the bottom
  expected_value = '<<-- | -->>'
  assert_match(expected_value, trim(getline(1)))
  assert_match(expected_value, trim(getline('$')))

  exe "norm q"
  assert_equal(1, winnr('$'))

  # test g:calendar_mark
  g:calendar_mark = 'right'
  var today = strftime('%d')
  expected_value = $'{today}\*'
  Calendar
  WaitForAssert(() => assert_equal(2, winnr('$')))
  assert_match(matchstr(getline('.'), today), today)
  exe "norm q"
  assert_equal(1, winnr('$'))

  g:calendar_mark = 'left-fit'
  expected_value = $'\*{today}'
  Calendar
  WaitForAssert(() => assert_equal(2, winnr('$')))
  assert_match(matchstr(getline('.'), today), today)
  exe "norm q"
  assert_equal(1, winnr('$'))

  # Test other opts
  g:calendar_mruler = 'Gen, Feb, Mar, Apr, Mag, Giu, Lug, Ago, Set, Ott, Nov, Dic'
  g:calendar_wruler = 'Do Lu Ma Me Gi Ve Sa'
  Calendar 2012, 1
  WaitForAssert(() => assert_equal(2, winnr('$')))
  
  expected_value =<< END
      <<-- | -->> 

     2011/12(Dic)     
 Do Lu Ma Me Gi Ve Sa 
              1  2  3 
  4  5  6  7  8  9 10 
 11 12 13 14 15 16 17 
 18 19 20 21 22 23 24 
 25 26 27 28 29 30 31 
 
     2012/1(Gen)      
 Do Lu Ma Me Gi Ve Sa 
  1  2  3  4  5  6  7 
  8  9 10 11 12 13 14 
 15 16 17 18 19 20 21 
 22 23 24 25 26 27 28 
 29 30 31             
 
     2012/2(Feb)      
 Do Lu Ma Me Gi Ve Sa 
           1  2  3  4 
  5  6  7  8  9 10 11 
 12 13 14 15 16 17 18 
 19 20 21 22 23 24 25 
 26 27 28 29          

      <<-- | -->> 
END
  assert_equal(expected_value, getline(1, '$')) 
  exe "norm q"
  assert_equal(1, winnr('$'))
  
  # start from monday
  g:calendar_monday = true
  CalendarVR 1990, 4

  expected_value =<< END
      <<-- | -->> 

     1990/3(Mar)      
 Lu Ma Me Gi Ve Sa Do 
           1  2  3  4 
  5  6  7  8  9 10 11 
 12 13 14 15 16 17 18 
 19 20 21 22 23 24 25 
 26 27 28 29 30 31    
 
     1990/4(Apr)      
 Lu Ma Me Gi Ve Sa Do 
                    1 
  2  3  4  5  6  7  8 
  9 10 11 12 13 14 15 
 16 17 18 19 20 21 22 
 23 24 25 26 27 28 29 
 30                   
 
     1990/5(Mag)      
 Lu Ma Me Gi Ve Sa Do 
     1  2  3  4  5  6 
  7  8  9 10 11 12 13 
 14 15 16 17 18 19 20 
 21 22 23 24 25 26 27 
 28 29 30 31          

      <<-- | -->> 
END

  echom assert_equal(expected_value, getline(1, '$')) 
  exe "norm q"
  assert_equal(1, winnr('$'))
  
  
  g:calendar_weeknm = 2 # WK 1
  CalendarVR 1989, 11
  
  expected_value =<< END
        <<-- | -->> 

       1989/10(Ott)        
 Lu Ma Me Gi Ve Sa Do      
                    1 WK39 
  2  3  4  5  6  7  8 WK40 
  9 10 11 12 13 14 15 WK41 
 16 17 18 19 20 21 22 WK42 
 23 24 25 26 27 28 29 WK43 
 30 31                WK44 
 
       1989/11(Nov)        
 Lu Ma Me Gi Ve Sa Do      
        1  2  3  4  5 WK44 
  6  7  8  9 10 11 12 WK45 
 13 14 15 16 17 18 19 WK46 
 20 21 22 23 24 25 26 WK47 
 27 28 29 30          WK48 
 
       1989/12(Dic)        
 Lu Ma Me Gi Ve Sa Do      
              1  2  3 WK48 
  4  5  6  7  8  9 10 WK49 
 11 12 13 14 15 16 17 WK50 
 18 19 20 21 22 23 24 WK51 
 25 26 27 28 29 30 31 WK52 

        <<-- | -->> 
END
  
  echom assert_equal(expected_value, getline(1, '$')) 
  exe "norm q"
  assert_equal(1, winnr('$'))

  # multiple months per calendar
  g:calendar_number_of_months = 5
  Calendar 1023, 9
  WaitForAssert(() => assert_equal(2, winnr('$')))

  expected_value =<< END
        <<-- | -->> 

        1023/8(Ago)        
 Lu Ma Me Gi Ve Sa Do      
     1  2  3  4  5  6 WK31 
  7  8  9 10 11 12 13 WK32 
 14 15 16 17 18 19 20 WK33 
 21 22 23 24 25 26 27 WK34 
 28 29 30 31          WK35 
 
        1023/9(Set)        
 Lu Ma Me Gi Ve Sa Do      
              1  2  3 WK35 
  4  5  6  7  8  9 10 WK36 
 11 12 13 14 15 16 17 WK37 
 18 19 20 21 22 23 24 WK38 
 25 26 27 28 29 30    WK39 
 
       1023/10(Ott)        
 Lu Ma Me Gi Ve Sa Do      
                    1 WK39 
  2  3  4  5  6  7  8 WK40 
  9 10 11 12 13 14 15 WK41 
 16 17 18 19 20 21 22 WK42 
 23 24 25 26 27 28 29 WK43 
 30 31                WK44 
 
       1023/11(Nov)        
 Lu Ma Me Gi Ve Sa Do      
        1  2  3  4  5 WK44 
  6  7  8  9 10 11 12 WK45 
 13 14 15 16 17 18 19 WK46 
 20 21 22 23 24 25 26 WK47 
 27 28 29 30          WK48 
 
       1023/12(Dic)        
 Lu Ma Me Gi Ve Sa Do      
              1  2  3 WK48 
  4  5  6  7  8  9 10 WK49 
 11 12 13 14 15 16 17 WK50 
 18 19 20 21 22 23 24 WK51 
 25 26 27 28 29 30 31 WK52 

        <<-- | -->> 
END

  echom assert_equal(expected_value, getline(1, '$')) 
  exe "norm q"
  assert_equal(1, winnr('$'))

  # eras
  g:calendar_erafmt = 'Heisei, -1988'

  Calendar 2000, 1
  WaitForAssert(() => assert_equal(2, winnr('$')))
  
  expected_value =<< END
        <<-- | -->> 

     Heisei11/12(Dic)      
 Lu Ma Me Gi Ve Sa Do      
        1  2  3  4  5 WK48 
  6  7  8  9 10 11 12 WK49 
 13 14 15 16 17 18 19 WK50 
 20 21 22 23 24 25 26 WK51 
 27 28 29 30 31       WK52 
 
      Heisei12/1(Gen)      
 Lu Ma Me Gi Ve Sa Do      
                 1  2 WK52 
  3  4  5  6  7  8  9 WK 1 
 10 11 12 13 14 15 16 WK 2 
 17 18 19 20 21 22 23 WK 3 
 24 25 26 27 28 29 30 WK 4 
 31                   WK5  
 
      Heisei12/2(Feb)      
 Lu Ma Me Gi Ve Sa Do      
     1  2  3  4  5  6 WK 5 
  7  8  9 10 11 12 13 WK 6 
 14 15 16 17 18 19 20 WK 7 
 21 22 23 24 25 26 27 WK 8 
 28 29                WK9  
 
      Heisei12/3(Mar)      
 Lu Ma Me Gi Ve Sa Do      
        1  2  3  4  5 WK 9 
  6  7  8  9 10 11 12 WK10 
 13 14 15 16 17 18 19 WK11 
 20 21 22 23 24 25 26 WK12 
 27 28 29 30 31       WK13 
 
      Heisei12/4(Apr)      
 Lu Ma Me Gi Ve Sa Do      
                 1  2 WK13 
  3  4  5  6  7  8  9 WK14 
 10 11 12 13 14 15 16 WK15 
 17 18 19 20 21 22 23 WK16 
 24 25 26 27 28 29 30 WK17 

        <<-- | -->> 
END

  echom assert_equal(expected_value, getline(1, '$'))
  exe "norm q"
  assert_equal(1, winnr('$'))

  # Teardown optional variables and reset of some variables
  g:calendar_number_of_months = 3
  g:calendar_navi_label = 'Prev, Today, Next'
  unlet g:calendar_monday
  unlet g:calendar_mruler
  unlet g:calendar_wruler
  unlet g:calendar_weeknm
  unlet g:calendar_erafmt

  :%bw!
enddef

def g:Test_syntax_highlight()

  Calendar 2020, 3
  WaitForAssert(() => assert_equal(2, winnr('$')))

  #2020/2(Feb)
  var linenr = 3
  var date_idx = getline(linenr)->match('\S') + 1
  var hi_group = synIDattr(synID(linenr, date_idx, 1), 'name')
  assert_match(hi_group, 'CalHeader')

  # Su Mo Tu ...
  linenr = 4
  var week_day = getline(linenr)->match('\S') + 1
  hi_group = synIDattr(synID(linenr, week_day, 1), 'name')
  assert_match(hi_group, 'CalRuler')

  # 8th line is this:
  # 16 17 18 19 20 21 22 
  linenr = 8
  # CalSunday
  var first_day_idx = getline(linenr)->match('\S') + 1
  hi_group = synIDattr(synID(linenr, first_day_idx, 1), 'name')
  assert_match(hi_group, 'CalSunday')

  # Check in the middle, column 5
  # No hlgroup
  var middle_idx = 5
  hi_group = synIDattr(synID(linenr, middle_idx, 1), 'name')
  assert_true(empty(hi_group))

  # Check end
  # CalSaturday
  var last_day_idx = len(getline(linenr)) - 1 
  hi_group = synIDattr(synID(linenr, last_day_idx, 1), 'name')
  assert_match(hi_group, 'CalSaturday')

  exe "norm q"
  assert_equal(1, winnr('$'))

  # Test CalendarH
  CalendarH 2020, 3

  #2020/2(Feb)
  linenr = 2
  date_idx = getline(linenr)->match('\S') + 1
  hi_group = synIDattr(synID(linenr, date_idx, 1), 'name')
  assert_match(hi_group, 'CalHeader')

  # Su Mo Tu ...
  linenr = 3
  week_day = getline(linenr)->match('\S') + 1
  hi_group = synIDattr(synID(linenr, week_day, 1), 'name')
  assert_match(hi_group, 'CalRuler')

  # February
  linenr = 8
  first_day_idx = getline(linenr)->match('\S') + 1
  hi_group = synIDattr(synID(linenr, first_day_idx, 1), 'name')
  assert_match(hi_group, 'CalSunday')

  middle_idx = 13
  hi_group = synIDattr(synID(linenr, middle_idx, 1), 'name')
  assert_true(empty(hi_group))

  last_day_idx = 22
  hi_group = synIDattr(synID(linenr, last_day_idx, 1), 'name')
  assert_match(hi_group, 'CalSaturday')

  # March
  first_day_idx = 26
  hi_group = synIDattr(synID(linenr, first_day_idx, 1), 'name')
  assert_match(hi_group, 'CalSunday')

  middle_idx = 30
  hi_group = synIDattr(synID(linenr, middle_idx, 1), 'name')
  assert_true(empty(hi_group))

  last_day_idx = 45
  hi_group = synIDattr(synID(linenr, last_day_idx, 1), 'name')
  assert_match(hi_group, 'CalSaturday')

  # April
  first_day_idx = 50
  hi_group = synIDattr(synID(linenr, first_day_idx, 1), 'name')
  assert_match(hi_group, 'CalSunday')

  middle_idx = 56
  hi_group = synIDattr(synID(linenr, middle_idx, 1), 'name')
  assert_true(empty(hi_group))

  last_day_idx = 68
  hi_group = synIDattr(synID(linenr, last_day_idx, 1), 'name')
  assert_match(hi_group, 'CalSaturday')

  exe "norm q"
  assert_equal(1, winnr('$'))

  :%bw!
enddef

def g:Test_hooks()

  def g:MyCalBegin()
    setreg('a', "Calendar started")
  enddef
  g:calendar_begin = 'g:MyCalBegin'

  def g:MyCalToday()
    setreg('b', "Calendar today")
  enddef
  g:calendar_today = 'g:MyCalToday'

  def g:MyCalEnd()
    setreg('c', "Calendar ended")
  enddef
  g:calendar_end = 'g:MyCalEnd'

  Calendar 1624, 12
  WaitForAssert(() => assert_equal(2, winnr('$')))
  var actual_value = getreg('a')
  assert_match("Calendar started", actual_value)

  # Select "Today" in the navigation panel on top
  exe "norm ggfT\<cr>"
  actual_value = getreg('b')
  assert_match("Calendar today", actual_value)

  exe "norm q"
  actual_value = getreg('c')
  assert_match("Calendar ended", actual_value)

  unlet g:calendar_begin
  unlet g:calendar_today
  unlet g:calendar_end

  :%bw!
enddef
