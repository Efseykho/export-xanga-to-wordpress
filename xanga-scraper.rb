require 'rubygems'
require 'mechanize'
gem 'hpricot', '>=0.7' #xml was broken in 0.6, it works in LAG for winx86 
                                              #you can try with previous versions but YMMV

if __FILE__ == $0
  print "Usage: XangaScraper.new( xanga_user_name , xanga_password).scrape( :max_blog_entries => 3 )"
end

#xanga scraper to dl all relevant blog entries
class XangaScraper
  
  attr_reader :agent
  attr_reader :blog
  attr_reader :options
  

  #TODO: at some point make pw optional
  def initialize(user,pw, opts = nil)
    @user = user
    @pw = pw
    @blog = nil
    
    @max_blog_entries = nil #as specified in scrape
    @curr_blog_entries = 1 #local loop variable
    
    @completed = false #stop scraping if @completed
    @options = opts #options which get filled in by templates 
    
    @doc = nil #Hpricot document representing the xml file
    
    @comment_id = 1 #represents fixed comment id, increased for each comment
    @comment_hash = Hash.new #how we store hierarchical comments
                                            # [key in xanga] => @comment_id

    #for now, just set options to default
    set_default_options if @options == nil 
    
    @agent = WWW::Mechanize.new{ |agent|
        # refreshes after login
       agent.follow_meta_refresh = true
    }
  end
  
  #sets the default options hash
  #this controls how the xml fields get filled out
  #check the defaults; not all are required
  def set_default_options(options = nil)
    #give some sensical options instead of blank elements
    @options = Hash.new
    @options[:default_title] = "My Awesome Title"
    @options[:default_link] = "http://default.wordpress.com"
    @options[:default_description] = "My Awesome Description"
    @options[:pub_date] = "Tue, 10 Mar 2009 00:12:59 +0000"
    @options[:base_blog_url] = "http://default.wordpress.com"
    @options[:creator] = "Hiro"
  end
  
  #main action of class
  #this will follow all links, modified by opts
  #and scrape found data
  #possibly options in 'options'
  # options[ :max_blog_entries] = max number of blog entries to dump out, inf if not specified
  def scrape(options = nil)
    @max_blog_entries = options[:max_blog_entries] if options != nil
    @completed = false
    
    #TODO: pw should be optional
    page = login #if @pw != nil #only do the login thing if you have pw
    page =goto_weblog(page)
    
    #create new xml document from template
    #at some point in future, you want to pass in non-default options here
    create_new_xml_document
    
    scrape_1_page(page)
    next_link = page.links.reject{|i| i.to_s != "Next 5 >>" }
    while  next_link.size == 1 and @completed != true do
      sleep(1)
      p "clicking on next link: #{next_link[0].uri.to_s}"
      page = @agent.click(next_link[0])
      scrape_1_page(page)
      
      #now update the next_link
      next_link = page.links.reject{|i| i.to_s != "Next 5 >>" }
    end
  
    #dump @doc out as the output
    file = File.new("wordpress.#{Time.now.strftime("%Y-%m-%d")}.xml", "w+")
    file.puts( @doc.inner_html )
    file.close
    
    @doc
  end
  
  
  #this will scrape 1month of data
  #everything is handled in a transaction block so no need to go back
  #INPUT: mechanize link
  #OUTPUT: none
  def scrape_1_page(page)
    p "scraping a page" #{link.href}"  
    blog_date_1 = nil #the first part of the pubDate field goes into here
    blog_body = nil #the body text goes here
    blog_date_2 = nil #the second part of the pubDate field goes into here
    comments_arr = nil #temporary storage for comments before they get added to main document
    
    #select on td id=maincontent
    page.search('#maincontent')[0].each_child{ |child|
      
      if @max_blog_entries != nil and @curr_blog_entries >= @max_blog_entries
        @completed = true
        p "reached max_blog_entries=#{@max_blog_entries}"
        return
      end
   
    if child.search('.blogheader').length != 0
      blog_date_1 = convert_xanga_header_to_wordpress_date(child.inner_html)
      p "blog head #{blog_date_1}" 
      #this is first part of date-time

    elsif child.search('.blogbody').length != 0
      #TODO: extract comments, number of views for blog
 
      #this is body of the blog
      blog_body = sanitize_blog_body(child.search("td")[1].inner_html)
      
      #extract the date of blog for archiving purposes
      #inside class blogbody, lives a class smalltext, and we want the inner_html of the second <a href> tag
      blog_date_2 = convert_to_usable_time(child.search('.blogbody')[0].search('.smalltext')[0].search("a")[1].inner_html)
      
      #create teh new document out of blogheader and blogfooter
      doc = create_new_xml_blog( blog_body, blog_date_1 + blog_date_2 )
      
      #catch comments here
      #inside class blogbody, lives a class smalltext, and we want the inner_html of the fifth <a href> tag
      if child.search('.blogbody')[0].search('.smalltext')[0].search("a")[4].inner_html != "add comments"
        comments_arr =scrape_comments( Hpricot::Elements[ child.search('.blogbody')[0].search('.smalltext')[0].search("a")[4] ].attr("href") )
        comments_arr.each { |comment| 
          doc.search("item").append(comment.inner_html.to_s)
          #p "adding comment here #{comment.inner_html.to_s}"
        }
        #dump_page(doc)
      end

      #add resulting document to the @doc object already created
      @doc.search("channel").append(doc.inner_html.to_s)

      @curr_blog_entries += 1
    end
      
    }
  end
  
  #this will click provided link and create a structure of comments for insertions into current blog
  #input: link of comments to scrape
  #output Hpricot document representing comments
  def scrape_comments(href)
    p "scraping comments #{href}"
    
    comments = Array.new
    
    
    #begin transaction to get comments
    @agent.transact {
      page = @agent.get(href)
      
      page.search(".ctextfooterwrap").each{ |elem|
        #each ctextfooterwrap is a comment
        #a textfooter wrap is composed of ctext and cfooter
        
        #create our blog comment template
        str = <<-eos
<wp:comment>
<wp:comment_id></wp:comment_id>
<wp:comment_author><![CDATA[]]></wp:comment_author>
<wp:comment_author_email></wp:comment_author_email>
<wp:comment_author_url></wp:comment_author_url>
<wp:comment_author_IP></wp:comment_author_IP>
<wp:comment_date></wp:comment_date>
<wp:comment_date_gmt></wp:comment_date_gmt>
<wp:comment_content><![CDATA[]]></wp:comment_content>
<wp:comment_approved>1</wp:comment_approved>
<wp:comment_type></wp:comment_type>
<wp:comment_parent>0</wp:comment_parent>
<wp:comment_user_id>0</wp:comment_user_id>
</wp:comment>
        eos
        
        doc = Hpricot.XML(str)
        
        #this gives us the string with type= "Posted 3/24/2009 8:45 PM by anon ymos - delete - reply"
        str_arr = elem.search(".cfooter").inner_text.split(" ")
        #wp:comment_date/wp:comment_date_gmt have format of: 2009-03-10 00:12:22
        str_arr[1] = str_arr[1].split("/") #first we must fix format of year
        
        str_arr[1][0]= "0" + str_arr[1][0].to_s if str_arr[1][0].to_s.size == 1  #we want month padded to 2 digits
        str_arr[1][1]= "0" + str_arr[1][1].to_s if str_arr[1][0].to_s.size == 1  #we want day padded to 2 digits
        
        str_arr[1] = str_arr[1][2] + "-" + str_arr[1][0] + "-" + str_arr[1][1]
        str_arr[2] = convert_to_usable_time(str_arr[2] + " " +  str_arr[3] ).split(" ")[0]
        str_arr[1] = str_arr[1] + " " + str_arr[2]
        
        p "date is #{str_arr[1]}"
        doc.search("wp:comment_date").inner_html = str_arr[1]
        doc.search("wp:comment_date_gmt").inner_html = str_arr[1]

        #set comment id to next value
        doc.search("wp:comment_id").inner_html = "#{@comment_id}"
        
        #author is found in str_arr at element index=5 and continues till we find element "-"
        temp = ""
        while str_arr[5] != "-"
          temp = temp + str_arr[5] + " "
          str_arr.delete_at(5)
        end
        
        #in case of anonymous commenter, they can leave a site url in the name
        #thanks be to glorious xanga dom-design engineer but we now have to take that out
        temp = temp.gsub(/\(.*\)/, "")
        
        while temp[-1] == 32
          temp.chop!
        end 
        
        doc.search("wp:comment_author").inner_html = "<![CDATA[#{temp}]]>"
        p "author= #{temp}"
        
        #author email is not present?
        #comment_author_IP is not present?
        
        # fill in comment_author_url
        #if cfooter contains 2, or 3  href tags, we've got an anonymous comment
        #if 2, then anonymous and no url provided
        #if 3, then anonymous and url provided
        temp = elem.search(".cfooter").search("a")
        if temp.length == 3 #first link is provided 'site' url
          temp[0] = temp[0].to_s
          temp[0] = temp[0].slice(/href=\".*\"/).gsub("href=\"","").gsub("\"","")
          
          p "comment author=#{temp[0]}"
          doc.search("wp:comment_author_url").inner_html = temp[0]
        elsif temp.length == 4 #second link is provided user that commented
          temp[1] = temp[1].to_s
          temp[1] = temp[1].slice(/href=\".*\"/).gsub("href=\"","").gsub("\"","")
          
          p "comment author=#{temp[1]}"
          doc.search("wp:comment_author_url").inner_html = temp[1]
        end
        
        #capture comment id for hierarchical sorting
        temp = elem.search(".cfooter").search("a[@onclick]").to_s
        temp = temp.slice( /direction=n#\d*\'/).gsub("direction=n#","")
        @comment_hash[temp.to_i] = @comment_id #register comment id
        p "key #{temp.to_i} added to comment id=#{@comment_id}"
        @comment_id += 1
        
        #capture if this elem has parent-id
        #ctext:class=teplyto x--PARENTID--x
        temp = elem.search(".ctext").search(".replyto")
        if temp.size == 1
          temp = temp[0].to_s
          temp = temp.slice!(/x--\d*--x/)
          temp.gsub!("x--","")
          temp.gsub!("--x","")
          
          #p "lookup parent-id= #{temp}"
          temp = @comment_hash[temp.to_i]
          
          p "parent id= #{temp}"
          doc.search("wp:comment_parent").inner_html = "#{temp.to_i}"
          
          #additionally, this takes a special key thingamajic
          doc.search("wp:comment_user_id").inner_html = "6074067"
          
        elsif temp.size > 1 #this should NEVER happen, cant have >1 replyto element
          p "This is an error!"
          throw Exception.new("More than 1 replyto element found")
        end #end: if temp.size == 1
        
        #finally, insert comment-content where it belongs
        temp = elem.search(".ctext").inner_text
        p "comment=#{temp}"
        doc.search("wp:comment_content").inner_html = "<![CDATA[#{temp}]]>"
        
        #add document model for the comment to the list of arrays
        comments.push(doc)
        
      }#end:page.search(".ctextfooterwrap").each{ |elem|
    }#end:@agent.transact {
    
    #TODO: figure out if we need to recurse further down to get next 25 comments?
    
    comments
  end
  

  
  #this takes output for login and goes to my actual weblog
  #INPUT: page returne by login
  #OUTPUT: page of my weblog
  def goto_weblog(page)
    #generally speaking, we want to goto "http://[username].xanga.com/

    page = @agent.click page.links.href("http://#{@user}.xanga.com/").first
  end
  
  
  #this should be called ONCE: it logs you in
  #INPUT: none but uses (@user,@pw)
  #OUTPUT: page returned by login process
  def login
    #this assumes we can get to signin from here
    login = @agent.get('http://www.xanga.com/signin.aspx')
    form = login.form('frmSigninRegister')
    
    #this assumes default domain is xanga
    form.txtSigninUsername = @user
    form.txtSigninPassword = @pw
    
    #this assumes first button will be the submit button
    page = @agent.submit(form, form.buttons.first)
  end
  
  #this is for debuggin
  def dump_page(page, name = "debug#{Time.now.strftime("%Y-%m-%d %H-%M")}" )
    str = page.inner_html.to_s
    file = File.new(name, "w+")
    file.puts(str)
    file.close
  end
  
  def write_blog_header(str)
    #p "creating blog with date=#{str}"
    str_conv = convert_xanga_header_to_date(str)
    @blog = File.new(str_conv + ".blog", "w+")
    @blog.puts("[BLOG DATE]\n")
    @blog.puts(str + "\n")
    @blog.flush
  end
  
  
  def write_blog_body(str)
    #assuming that @blog has already been created

    @blog.puts("[BLOG BODY]\n")
    @blog.puts(str + "\n")
    @blog.flush
  end
  
  #we create a new xml document here
  #we use the template file "wordpress_template.xml"
  #options = hash of options to fill in
  def create_new_xml_document( options = nil)
    p "new xml doc created!"
    
    blog_doc = <<-eos
<?xml version="1.0" encoding="UTF-8"?>
<!-- This is a WordPress eXtended RSS file generated by WordPress as an export of your blog. -->
<!-- It contains information about your blog's posts, comments, and categories. -->
<!-- You may use this file to transfer that content from one site to another. -->
<!-- This file is not intended to serve as a complete backup of your blog. -->

<!-- To import this information into a WordPress blog follow these steps. -->
<!-- 1. Log into that blog as an administrator. -->
<!-- 2. Go to Tools: Import in the blog's admin panels (or Manage: Import in older versions of WordPress). -->
<!-- 3. Choose "WordPress" from the list. -->
<!-- 4. Upload this file using the form provided on that page. -->
<!-- 5. You will first be asked to map the authors in this export file to users -->
<!--    on the blog.  For each author, you may choose to map to an -->
<!--    existing user on the blog or to create a new user -->
<!-- 6. WordPress will then import each of the posts, comments, and categories -->
<!--    contained in this file into your blog -->

<!-- generator="WordPress/MU" created="2009-03-10 00:13"-->
<rss version="2.0"
	xmlns:excerpt="http://wordpress.org/export/1.0/excerpt/"
	xmlns:content="http://purl.org/rss/1.0/modules/content/"
	xmlns:wfw="http://wellformedweb.org/CommentAPI/"
	xmlns:dc="http://purl.org/dc/elements/1.1/"
	xmlns:wp="http://wordpress.org/export/1.0/"
>

<channel>
	<title>xxx</title>
	<link>xxx</link>
	<description>xxx</description>
	<pubDate>xxx</pubDate>
	<generator>http://wordpress.org/?v=MU</generator>
	<language>en</language>
	<wp:wxr_version>1.0</wp:wxr_version>
	<wp:base_site_url>http://wordpress.com/</wp:base_site_url>
	<wp:base_blog_url>xxx</wp:base_blog_url>
	<wp:category><wp:category_nicename>uncategorized</wp:category_nicename><wp:category_parent></wp:category_parent><wp:cat_name><![CDATA[Uncategorized]]></wp:cat_name></wp:category>
	<image>
		<url>http://www.gravatar.com/blavatar/bc8a29036e9d9925e702dcf90996d0cd?s=96&#038;d=http://s.wordpress.com/i/buttonw-com.png</url>
		<title>xxx</title>
		<link>xxx</link>
	</image>
  
</channel>
</rss>
    eos
    
    doc = Hpricot.XML(blog_doc)
    
    #change created date to be right-now
    #element at fixed-offset 30
    #<!-- generator="WordPress/MU" created="2009-03-10 00:13"-->
    doc.search("*")[30].swap(
      "<!-- generator=\"WordPress/MU\" created=\"#{Time.now.strftime("%Y-%m-%d %H:%M")}\"-->"
    )
    
    #replace default_title, default_link, the name of the blog and link to blog (wordpress), respectively
    doc.search("title")[0].inner_html = @options[:default_title]
    doc.search("title")[1].inner_html = @options[:default_title]
    doc.search("link")[0].inner_html = @options[:default_link]
    doc.search("link")[1].inner_html = @options[:default_link]

    #replace default_description, pub_date
    doc.search("description").inner_html = @options[:default_description]
    doc.search("pubDate").inner_html = @options[:pub_date]
    doc.search("wp:base_blog_url").inner_html = @options[:base_blog_url]

    @doc = doc
  end
  
  #this fills in and creates a new xml fragment representing the blog body passed in
  #it also fills in params using @options hash
  #body = body of blog
  #time = time formatted as Tue, 10 Mar 2009 00:12:59 +0000
  def create_new_xml_blog( body, time )
    p "new xml doc created for time=#{time}"
    
  #this is our template for a an individual entry in the blog import file
  item_template = <<-eos
<item>
<title>xxx</title>
<link>xxx</link>
<pubDate>xxx</pubDate>
<dc:creator><![CDATA[xxx]]></dc:creator>

		<category><![CDATA[Uncategorized]]></category>

		<category domain="category" nicename="uncategorized"><![CDATA[Uncategorized]]></category>

<guid isPermaLink="false">xxx</guid>
<description></description>
<content:encoded><![CDATA[xxx]]></content:encoded>
<excerpt:encoded><![CDATA[]]></excerpt:encoded>
<wp:post_id>xxx</wp:post_id>
<wp:post_date>xxx</wp:post_date>
<wp:post_date_gmt>xxx</wp:post_date_gmt>
<wp:comment_status>closed</wp:comment_status>
<wp:ping_status>closed</wp:ping_status>
<wp:post_name>xxx</wp:post_name>
<wp:status>publish</wp:status>
<wp:post_parent>0</wp:post_parent>
<wp:menu_order>0</wp:menu_order>
<wp:post_type>post</wp:post_type>
<wp:post_password></wp:post_password>
</item>

        eos
        
    doc = Hpricot.XML(item_template)
    
    #xanga names entries on date, so we will do same
    doc.search("title")[0].inner_html = "#{time.gsub(" +0000","")}"
    #link is constructed as follows: [base_blog_url]/[YYYY]/[MM]/[DD]/[title.downcase]
    #for dates, this looks like: [base_blog_url]/[YYYY]/[MM]/[DD]/tue-10-mar-2009-001259-0000/, for example
    doc.search("link")[0].inner_html =  "#{@options[:base_blog_url]}/#{Time.now.strftime("%Y")}/#{Time.now.strftime("%m")}/#{Time.now.strftime("%d")}/#{time.downcase.gsub(",", "").gsub(":","").gsub(" +","-").gsub(" ","-")}/"
    
    #pubDate is 'time' passed in
    doc.search("pubDate")[0].inner_html = "#{time}"
    #the creator is the username that gets credit for the posting i guess
    doc.search("dc:creator")[0].inner_html = "<![CDATA[#{@options[:creator]}]]>"
    #guid is, as far as i can tell follows base_blog_url/?p=N format, where N=sequence of blog 
    doc.search("guid")[0].inner_html =  "#{@options[:base_blog_url]}/?p=#{@curr_blog_entries}"
    #content:encoded is the blog body passed here
    doc.search("content:encoded")[0].inner_html =  "<![CDATA[#{body}]]>"
    #wp:post_id is as far as i can tell, just the sequential ordering of imported entries 
    doc.search("wp:post_id")[0].inner_html =  "#{@curr_blog_entries}"

    #I've a conflict with my Time class; so I have to hack around, so sorry
    #input: time formatted as Tue, 10 Mar 2009 00:12:59 +0000
    #output:  2009-03-10 00:12:59, for example
    def convert_to_wp_post_date(time)
      ret = time.split(" ")
      month_value = { 'JAN' => 1, 'FEB' => 2, 'MAR' => 3, 'APR' => 4, 'MAY' => 5, 'JUN' => 6, 'JUL' => 7, 'AUG' => 8, 'SEP' => 9, 'OCT' =>10, 'NOV' =>11, 'DEC' =>12 }
      ret[2] = month_value[ ret[2].upcase ] 
      ret[2] = "0" + ret[2].to_s if ret[2].to_s.size == 1  #we want month padded to 2 digits
      ret[1] = "0" + ret[1].to_s if ret[1].to_s.size == 1  #we want day padded to 2 digits
      
       "#{ret[3]}-#{ret[2]}-#{ret[1]} #{ret[4]}"
     end
     
    #wp:post_date /wp:post_date_gmt is yet another format for the time field passed in
    #it looks like: 2009-03-10 00:12:59, for example
    doc.search("wp:post_date")[0].inner_html =  "#{convert_to_wp_post_date(time)}"
    doc.search("wp:post_date_gmt")[0].inner_html =  "#{convert_to_wp_post_date(time)}"
    #wp:post_name with xanga, it is same asthe last part of the link tag
    doc.search("wp:post_name")[0].inner_html =  "#{time.downcase.gsub(",", "").gsub(":","").gsub(" +","-").gsub(" ","-")}"

    doc
  end

  #input: HH:MM [AM|PM]"
  #output: 00:12:59 +0000
  def convert_to_usable_time(xanga_time)
        arr = xanga_time.split(" ")
        ret = arr[0]
        ret.insert(0,"0") if arr[0].length == 4 #pad left-most zero
        
        if arr[1] == "PM" #add 12 to it
          str = ret.slice(0,2)
          0.upto(11){ str.succ! } 
          ret[0,2] = str
        end
        
        ret.concat(":00 +0000")
      end
      
  # xanga-headings are in AAA, BBB CCC, YYYY format
  # where AAA = Monday-Sunday,
  #BBB = January-December
  # CCC = 1-31
  # YYYY = year 
  #
  # How wordpress likes it is:"Tue, 10 Mar 2009 "
  def convert_xanga_header_to_wordpress_date(str)
    arr = str.split(" ") #split on spaces
    
    raise "Error in convert_xanga_header_to_date with value=#{str}" if arr.size != 4 
    
    #get rid of commas
    arr[0].chomp!(",") 
    arr[2].chomp!(",")
    
    arr[0] = case arr[0]
        when "Sunday"
          Time::RFC2822_DAY_NAME[0]
        when "Monday"
          Time::RFC2822_DAY_NAME[1]
        when "Tuesday"
          Time::RFC2822_DAY_NAME[2]
        when "Wednesday"
          Time::RFC2822_DAY_NAME[3]
        when "Thursday"
          Time::RFC2822_DAY_NAME[4]
        when "Friday"
          Time::RFC2822_DAY_NAME[5]
        when "Saturday"
          Time::RFC2822_DAY_NAME[6]
        else
          raise "Error in convert_xanga_header_to_date with value=#{arr[0]}"
        end
        
      arr[1] = case arr[1]
        when "January"
          Time::RFC2822_MONTH_NAME[0]
        when "February"
          Time::RFC2822_MONTH_NAME[1]
        when "March"
          Time::RFC2822_MONTH_NAME[2]
        when "April"
          Time::RFC2822_MONTH_NAME[3]
        when "May"
          Time::RFC2822_MONTH_NAME[4]
        when "June"
          Time::RFC2822_MONTH_NAME[5]
        when "July"
          Time::RFC2822_MONTH_NAME[6]
        when "August"
          Time::RFC2822_MONTH_NAME[7]
        when "September"
          Time::RFC2822_MONTH_NAME[8]
        when "October"
          Time::RFC2822_MONTH_NAME[9]
        when "November"
          Time::RFC2822_MONTH_NAME[10]
        when "December"
          Time::RFC2822_MONTH_NAME[11]          
        else
          #p "Error in convert_xanga_header_to_date with value=#{arr[0]}"
          raise "Error in convert_xanga_header_to_date with value=#{arr[0]}"
        end
        
        return "#{arr[0]}, #{arr[2]} #{arr[1]} #{arr[3]} "
  end
  
  #strips h4 heading and replace <Br> with \n
  #returns newly sanitized string
  def sanitize_blog_body(str)
    ret = str.gsub("<h4 class=\"itemTitle\"></h4>", " ")
    ret.gsub!("<br />","\n")
  end
  
end