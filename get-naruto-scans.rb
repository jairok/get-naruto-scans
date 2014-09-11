#!/usr/bin/ruby

# Downloads the latest chapter of Naruto from narutobase.net
# =========================================================
# Downloads the latest chapters from narutobase.net and convert them to pdf.   
# and convert it to pdf.
# The script ends when it get a 404 for a chapter.

require 'rubygems'
require 'fileutils'
require 'open-uri'
require 'zip/zipfilesystem'
require 'yaml'
require 'colorize'

SETTINGS_FILE = "settings.yml"
LATEST_CHAPTER_DOWNLOADED_FILE = "latest_chapter_downloaded.yml"
DOWNLOAD_FOLDER_DEFAULT = File.join(ENV["HOME"], "Downloads/Naruto_chapters")
REMOTE_URL = "http://narutobase.net/downloads/naruto-manga"
FILE_FORMAT = '.zip'

## Ensures a folder exists
def ensure_folder_exists(folder_path)
  if(!File.exists?(folder_path))
    FileUtils.makedirs(folder_path)
    puts "Folder #{folder_path} created."
  end
end

## Downloads a file from a remote source to a local destination
def download_file(remote_url,local_url)
  puts "Downloading #{remote_url} ..."
  begin
    stream = open(remote_url).read
  rescue OpenURI::HTTPError => e
    raise e
  else
    File.open(local_url, 'wb'){ |file| file.write(stream)}
    puts"...Success,  downloaded to #{local_url}."
  end
end

## Unzip a zip file to a destination folder
def unzip_file(zip_path, destination_folder)
  begin
    ensure_folder_exists(destination_folder)
    
    Zip::ZipFile.open(zip_path) { |zip_file|
     zip_file.each { |f|
       f_path=File.join(destination_folder, f.name)
       FileUtils.mkdir_p(File.dirname(f_path))
       zip_file.extract(f, f_path) unless File.exist?(f_path)
     }
    }
  rescue StandardError => e
    raise e
  else
    FileUtils.rm_rf(zip_path) 
    puts"... Success,  unzipped to #{destination_folder}."
  end
end

## Convert all *.jpg from an image folder into a single .pdf
def convert_to_pdf(images_folder, pdf_file_path)
  puts "Converting images to pdf"
  begin
    files_list = ""  
    
    Dir["#{images_folder}/**/*.jpg"].each do |f|
      files_list << "\""<< f << "\" "
    end
    
    `/usr/local/bin/convert #{files_list} #{pdf_file_path}`
    rescue StandardError => e
      raise e
    else
      FileUtils.rm_rf(images_folder)
      puts"... Success,  #{pdf_file_path} created."
    end
end

## Load settings in global variables
def load_settings()
  settings = File.exists?(SETTINGS_FILE) ? YAML.load_file(SETTINGS_FILE):{"settings" => {}}
  download_folder = settings["settings"]["download_folder"]
  $download_folder = !download_folder.to_s == '' ? download_folder : DOWNLOAD_FOLDER_DEFAULT
  verbose = settings["settings"]["verbose"]
  $verbose = verbose == 'yes' ? true : false
end

## Load the latest chapter downloaded
def load_latest_chapter_downloaded()
  if(!File.exists?(LATEST_CHAPTER_DOWNLOADED_FILE))
    write_latest_chapter_downloaded("???")
  end
  $latest_chapter_downloaded = YAML.load_file(LATEST_CHAPTER_DOWNLOADED_FILE)
  raise "You need to adjust the latest chapter downloaded in #{LATEST_CHAPTER_DOWNLOADED_FILE}" unless $latest_chapter_downloaded.is_a? Integer
end

## Write the latest chapter downloaded
def write_latest_chapter_downloaded(latest_chapter_downloaded)
  File.open("#{LATEST_CHAPTER_DOWNLOADED_FILE}", 'w') { |file| file.write(latest_chapter_downloaded.to_yaml)}
end

############
# MAIN     #
############

$download_folder
$latest_chapter_downloaded
$verbose

begin
    # Load settings and latest chapter downloaded
    load_settings()
    load_latest_chapter_downloaded()
    
    # Ensure the download folder exists
    ensure_folder_exists($download_folder)
rescue StandardError => e
    puts "#{e}".red
    abort
end

puts "Starting downloading Naruto's scans"
puts "==================================="

latest_chapter_downloaded_index = $latest_chapter_downloaded.to_i
next_chapter_to_download_index = latest_chapter_downloaded_index + 1
retry_counter = 0;

loop do
  begin
    next_chapter_to_download = next_chapter_to_download_index.to_s
    
    # Increment the retry counter each time the loop begin
    # and reset it at the end of the loop.
    retry_counter += 1 
    
    # Download the scan
    remote_zip_url = File.join(REMOTE_URL, next_chapter_to_download) + FILE_FORMAT
    local_zip_path = File.join($download_folder, next_chapter_to_download) + FILE_FORMAT
    download_file(remote_zip_url, local_zip_path) unless File.exists?local_zip_path

    # Unzip the scan
    unzip_folder_path = File.join($download_folder, next_chapter_to_download)
    unzip_file(local_zip_path, unzip_folder_path) if File.exists?local_zip_path

    # Create the pdf from the scan's images
    pdf_file_path = unzip_folder_path + ".pdf"
    convert_to_pdf(unzip_folder_path, pdf_file_path)
    
    # Save the scan number as the latest downloaded into the file
    latest_chapter_downloaded_index = next_chapter_to_download_index
    write_latest_chapter_downloaded(latest_chapter_downloaded_index)
  
    # Increment before continuing ...
    next_chapter_to_download_index += 1
    
    # Reset the retry counter
    retry_counter = 0
    
    puts "Episode \##{latest_chapter_downloaded_index} done".green
    
  rescue OpenURI::HTTPError => e
      puts "\tError: #{e}".red unless $verbose == false
      if "#{e.io.status[0]}" == "404"
        puts "Obviously, the episode #{latest_chapter_downloaded_index} was the latest.".red
        puts "Otherwise, try to adjust the chapter number in latest_chapter_downloaded.yml".yellow
        break
      end
  rescue StandardError => e
      puts "\tError: #{e}".red unless $verbose == false
      if retry_counter >= 3
        puts "Too many errors to continue, please check the trace.".red
        break
      end
  end
end