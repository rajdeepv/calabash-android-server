require 'rexml/document'
require 'rexml/xpath'
require 'zip/zip'
require 'tempfile'

include REXML

def package_name(app)
  require 'rexml/document'
  require 'rexml/xpath'

  manifest = Document.new(manifest(app))
  manifest.root.attributes['package']
end

def main_activity(app)
  manifest = Document.new(manifest(app))
  main_activity = manifest.elements["//action[@name='android.intent.action.MAIN']/../.."].attributes['name']
  #Handle situation where main activity is on the form '.class_name'
  if main_activity.start_with? "."
    main_activity = package_name(app) + main_activity
  elsif not main_activity.include? "." #This is undocumentet behaviour but Android seems to accept shorthand naming that does not start with '.'
    main_activity = "#{package_name(app)}.#{main_activity}"
  end
  main_activity
end

def manifest(app)
  `java -jar "#{File.dirname(__FILE__)}/lib/manifest_extractor.jar" "#{app}"`
end

def checksum(file_path)
  require 'digest/md5'
  Digest::MD5.file(file_path).hexdigest
end

def test_server_path(apk_file_path)
  "test_servers/#{checksum(apk_file_path)}_#{Calabash::Android::VERSION}.apk"
end

def sign_apk(app_path, dest_path)
  unaligned_path = Tempfile.new('unaligned.apk').path
  keystore = read_keystore_info()

  if is_windows?
    jarsigner_path = "\"#{ENV["JAVA_HOME"]}/bin/jarsigner.exe\""
    zipalign_path = "\"#{ENV["ANDROID_HOME"]}/tools/zipalign.exe\""
  else
    jarsigner_path = "jarsigner"
    zipalign_path = "\"#{ENV["ANDROID_HOME"]}/tools/zipalign\""
  end


  cmd = "#{jarsigner_path} -sigalg MD5withRSA -digestalg SHA1 -signedjar #{unaligned_path} -storepass #{keystore["keystore_password"]} -keystore \"#{File.expand_path keystore["keystore_location"]}\" #{app_path} #{keystore["keystore_alias"]}"
  log cmd
  unless system(cmd)
    puts "jarsigner command: #{cmd}"
    raise "Could not sign app (#{app_path}"
  end

  cmd = "#{zipalign_path} 4 #{unaligned_path} #{dest_path}"
  log cmd
  unless system(cmd)
    puts cmd
    raise "Could not sign app. Zipalign failed"
  end
end

def read_keystore_info
  if File.exist? ".calabash_settings"
    JSON.parse(IO.read(".calabash_settings"))
  else
    {
    "keystore_location" => "#{ENV["HOME"]}/.android/debug.keystore",
    "keystore_password" => "android",
    "keystore_alias" => "androiddebugkey",
    "keystore_alias_password" => "android"
    }
  end
end

def is_windows?
  require 'rbconfig'
  (RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/)
end

def log(message, error = false)
  $stdout.puts "#{Time.now.strftime("%Y-%m-%d %H:%M:%S")} - #{message}" if (error or ARGV.include? "-v" or ARGV.include? "--verbose")
end