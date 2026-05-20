EXE_EXT = Gem.win_platform? ? ".exe" : ""

task :default => "./hunaftool#{EXE_EXT}" do
end

task :check => [:check_ruby, :check_crystal] do
end

task "./hunaftool#{EXE_EXT}" => "hunaftool.rb" do
  sh "crystal build --release --static hunaftool.rb"
end

task :check_ruby do
  sh "ruby tests/run-hunaftool-tests.rb \"ruby hunaftool.rb\" tests"
end

task :check_crystal => "./hunaftool#{EXE_EXT}" do
  sh "ruby tests/run-hunaftool-tests.rb \"./hunaftool#{EXE_EXT}\" tests"
end
