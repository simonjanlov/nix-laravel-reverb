<?php

# Imports /run/laravel-reverb/reverbConfig.json into php environment

$filename = "/run/laravel-reverb/reverbConfig.json";
$handle = fopen($filename, "r");
$contents = fread($handle, filesize($filename));
fclose($handle);

return json_decode($contents, true);
