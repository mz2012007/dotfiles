#!/bin/bash

USER_HOME="/home/$(whoami)"  # مجلد المستخدم تلقائي

days=(الأحد الإثنين الثلاثاء الأربعاء الخميس الجمعة السبت)
months=(يناير فبراير مارس أبريل مايو يونيو يوليو أغسطس سبتمبر أكتوبر نوفمبر ديسمبر)

while true; do
  now=$(date '+%H %M %S %w %d %m %Y')
  read -r hour minute second day_index day_num month_num year <<< "$now"

  ampm="AM"
  h12=$hour
  if (( hour == 0 )); then
    h12=12
  elif (( hour > 12 )); then
    h12=$((hour - 12))
    ampm="PM"
  fi

  time_formatted=$(printf "%02d:%02d:%02d %s" $h12 $minute $second $ampm)

  day_name=${days[$day_index]}
  month_name=${months[$((10#$month_num - 1))]}
  full_date="$day_name، $day_num $month_name $year"

  echo "$time_formatted"
  echo "$full_date" > "$USER_HOME/polybar_date_ar.txt"

  sleep 1
done

