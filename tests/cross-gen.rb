# This script generates the crossproduct testcases
refdata = <<-END
SET UTF-8
TRY анісырлеокятдувзмпцўбгґчьшхйэжюёАНПЯІСКТВМДЗГҐУЛБфШЁХРЧЦЮЖОФЎЭЕЫЙЬ
FULLSTRIP
NEEDAFFIX z
PFX A # 2
PFX A лыжка сьвіньня лыжка
PFX A лыж шчот лыж
SFX B # 1
SFX B екар ыжка лекар
SFX C # 1
SFX C ка 0/ABz ка
PFX X # 2
PFX X аая бю ааяр
PFX X ааа ба ааа
SFX Y # 1
SFX Y ааа яв/Z ааа
SFX Z # 1
SFX Z в ргер в
END

refdic = <<-END
4
аааа/XY
ааааа/XY
аааааа/XY
лекарка/C
END

reftxt = <<-END
аааа
ааааа
аааааа
аааяв
аааяргер
ааяв
ааяргер
аяв
аяргер
баа
бааа
баааа
баяв
баяргер
бюргер
лекар
лекарка
лыжка
сьвіньня
шчотка
END

0.upto(2 ** 6 - 1) do |idx|
  cnt = -1
  data = refdata.gsub(/\#/) {
    (idx & (1 << (cnt += 1)) != 0) ? "Y" : "N"
  }
  filesuff = sprintf("%02d", idx)
  File.write("cross" + filesuff + ".aff", data)
  File.write("cross" + filesuff + ".dic", refdic)
  File.write("cross" + filesuff + ".good", reftxt)
  filtered_txt = `hunspell -d #{"cross" + filesuff} -G #{"cross" + filesuff + ".good"}`
  File.write("cross" + filesuff + ".good", filtered_txt)
end
