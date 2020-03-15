require 'json'

require 'httparty'
require 'redis'
require 'sinatra'


# ISDH = Indiana State Department of Health
#
# URLs retrieved from the AJAX requests made from
# https://isdh.maps.arcgis.com/apps/opsdashboard/index.html#/255e4039e3dd4d8780d8da7b9b599d70
class CachedIsdhMetrics
  attr_reader :redis

  EXPIRE_IN_ONE_HOUR = 60 * 60

  def initialize(redis:)
    @redis = redis
  end

  def tested_positive
    cache_or_run(:tested_positive) do
      response = HTTParty.get("https://services5.arcgis.com/f2aRfVsQG7TInso2/arcgis/rest/services/Coronavirus/FeatureServer/0/query?f=json&where=Measure%3D%27Positives%27&returnGeometry=false&spatialRel=esriSpatialRelIntersects&outFields=*&resultOffset=0&resultRecordCount=50&cacheHint=true")
      JSON.parse(response, symbolize_names: true).dig(:features, 0, :attributes, :Counts)
    end.to_i
  end

  def tested_total
    cache_or_run(:tested_total) do
      response = HTTParty.get("https://services5.arcgis.com/f2aRfVsQG7TInso2/arcgis/rest/services/Coronavirus/FeatureServer/0/query?f=json&where=Measure%3D%27Tested%27&returnGeometry=false&spatialRel=esriSpatialRelIntersects&outFields=*&resultOffset=0&resultRecordCount=50&cacheHint=true")
      JSON.parse(response, symbolize_names: true).dig(:features, 0, :attributes, :Counts)
    end.to_i
  end

  def tested_negative
    tested_total - tested_positive
  end

  def deaths
    cache_or_run(:deaths) do
      response = HTTParty.get("https://services5.arcgis.com/f2aRfVsQG7TInso2/arcgis/rest/services/Coronavirus/FeatureServer/0/query?f=json&where=Measure%3D%27Deaths%27&returnGeometry=false&spatialRel=esriSpatialRelIntersects&outFields=*&resultOffset=0&resultRecordCount=50&cacheHint=true")
      JSON.parse(response, symbolize_names: true).dig(:features, 0, :attributes, :Counts)
    end.to_i
  end

  def updated_at
    cache_or_run(:updated_at) do
      response = HTTParty.get("https://services5.arcgis.com/f2aRfVsQG7TInso2/arcgis/rest/services/Coronavirus/FeatureServer/0/query?f=json&where=Measure%3D%27Update%20Text%27&returnGeometry=false&spatialRel=esriSpatialRelIntersects&outFields=*&resultOffset=0&resultRecordCount=1&cacheHint=true")
      # "MeastureText"? ¯\_(ツ)_/¯
      JSON.parse(response, symbolize_names: true).dig(:features, 0, :attributes, :MeastureText)
    end
  end

  private
  def cache_or_run(key, &block)
    if redis.exists(key)
      redis.get(key)
    else
      response = yield
      puts "Setting #{key} to #{response.inspect} for 1 hour"
      redis.set(key, response, ex: EXPIRE_IN_ONE_HOUR)

      response
    end
  end
end

redis = Redis.new(url: ENV["REDIS_URL"])
isdh_metrics = CachedIsdhMetrics.new(redis: redis)

get '/api' do
  content_type :json

  {
    state: "IN",
    tested_positive: isdh_metrics.tested_positive,
    tested_negative: isdh_metrics.tested_negative,
    tested_total: isdh_metrics.tested_total,
    deaths: isdh_metrics.deaths,
    updated_at: isdh_metrics.updated_at,
  }.to_json
end
