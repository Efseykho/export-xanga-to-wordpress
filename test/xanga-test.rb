$:.unshift File.join(File.dirname(__FILE__), ".." )

require "test/unit"
require "xanga-scraper.rb"
 
 class TestXangaScraper < Test::Unit::TestCase
 
   def setup
    @scraper = XangaScraper.new("xxx","yyy")
  end
 
  def teardown
    # Nothing really
  end
 
    
    def test_convert_to_usable_time
      #for AM-time, no compensation
      str = @scraper.convert_to_usable_time("02:59 AM")
      assert_equal(str, "02:59:00 +0000")
      
      #for PM, must add 12 hours to time
      str = @scraper.convert_to_usable_time("02:59 PM")
      assert_equal(str, "14:59:00 +0000")
      
      #edge-case #1
      str = @scraper.convert_to_usable_time("00:00 PM")
      assert_equal(str, "12:00:00 +0000")
      
      #edge-case #2
      str = @scraper.convert_to_usable_time("00:00 AM")
      assert_equal(str, "00:00:00 +0000")      
    end
 
 
   # xanga-headings are in AAA, BBB CCC, YYYY format
  # where AAA = Monday-Sunday,
  #BBB = January-December
  # CCC = 1-31
  # YYYY = year 
  #
  # How wordpress likes it is:"Tue, 10 Mar 2009 "
  def test_convert_xanga_header_to_wordpress_date
    str = @scraper.convert_xanga_header_to_wordpress_date("Sunday, April 30, 2006")
    assert_equal(str, "Sun, 30 Apr 2006 ")    

    str = @scraper.convert_xanga_header_to_wordpress_date("Monday, April 03, 2006")
    assert_equal(str, "Mon, 03 Apr 2006 ")    
    
    #malformed entries
    #
    assert_raise(RuntimeError) do #missing year
      str = @scraper.convert_xanga_header_to_wordpress_date("Monday, April 03, ")
    end
    
    assert_raise(RuntimeError) do #no space between
      str = @scraper.convert_xanga_header_to_wordpress_date("Monday, April 03,2006")
    end
    
    assert_raise(RuntimeError) do #malformed dayofweek
      str = @scraper.convert_xanga_header_to_wordpress_date("Mon, April 03, 2006")
    end
    
    assert_raise(RuntimeError ) do #malformed month
      str = @scraper.convert_xanga_header_to_wordpress_date("Monday, Apr 03, 2006")
    end    
  end #def test_convert_xanga_header_to_wordpress_date
  
  
 end #class TestXangaScraper < Test::Unit::TestCase