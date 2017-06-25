require 'net/http'
require 'json'
require 'open-uri'
require 'hpricot'
require 'dotenv'
Dotenv.load

# Look up pet information from PetFinder or PetHarbor
module PetFetcher
  extend self

  # rubocop:disable AccessorMethodName
  def get_petfinder_pet
    uri = URI('http://api.petfinder.com/pet.getRandom')
    params = {
      format:    'json',
      key:        ENV.fetch('petfinder_key'),
      shelterid:  ENV.fetch('petfinder_shelter_id'),
      output:    'full'
    }
    uri.query = URI.encode_www_form(params)
    response = Net::HTTP.get_response(uri)

    raise 'PetFinder api request failed' unless response.is_a? Net::HTTPSuccess

    json = JSON.parse(response.body)
    pet_json = json['petfinder']['pet']
    {
      pic:   get_photo(pet_json),
      link:  "https://www.petfinder.com/petdetail/#{pet_json['id']['$t']}",
      name:  pet_json['name']['$t'].capitalize,
      description: [
        get_petfinder_option(pet_json['options']),
        get_petfinder_sex(pet_json['sex']['$t']),
        get_petfinder_breed(pet_json['breeds'])
      ].compact.join(' ').downcase
    }
  end

  def get_petharbor_pet
    uri = URI('http://petharbor.com/petoftheday.asp')

    params = {
      shelterlist: "\'#{ENV.fetch('petharbor_shelter_id')}\'",
      type: get_petharbor_pet_type,
      availableonly: '1',
      showstat: '1',
      source: 'results'
    }
    uri.query = URI.encode_www_form(params)
    response = Net::HTTP.get_response(uri)

    raise 'PetHarbor request failed' unless response.is_a? Net::HTTPSuccess

    # The html response comes wrapped in some js :(
    response_html = response.body.gsub(/^document.write\s+\(\"/, '')
    response_html = response_html.gsub(/\"\);/, '')

    doc = Hpricot(response_html)
    pet_url = doc.at('//a').attributes['href']
    pet_url = pet_url.gsub('\"', '').delete('\\')
    pet_pic_html = doc.at('//a').inner_html
    pet_pic_url = pet_pic_html.match(/SRC=\\\"(?<url>.+)\\\"\s+border/)['url']
    table_cols = doc.search('//td')
    name = table_cols[1].inner_text.match(/^(?<name>\w+)\s+/)['name'].capitalize
    description = table_cols[3].inner_text.downcase
    {
      pic:   pet_pic_url,
      link:  pet_url,
      name:  name,
      description: description
    }
  end

  def self.get_photo(pet)
    return if pet['media']['photos']['photo'].nil?

    pet['media']['photos']['photo'][2]['$t']
  end

  private

  def get_petfinder_sex(sex_abbreviation)
    sex_abbreviation.casecmp('f').zero? ? 'female' : 'male'
  end

  def get_petharbor_pet_type
    ENV.fetch('petharbor_pet_types').split.sample
  end

  PETFINDER_ADJECTIVES = {
    'housebroken' => 'house trained',
    'housetrained' => 'house trained',
    'noClaws'     => 'declawed',
    'altered'     => 'altered',
    'noDogs'      => nil,
    'noCats'      => nil,
    'noKids'      => nil,
    'hasShots'    => nil
  }.freeze

  def get_petfinder_option(option_hash)
    if option_hash['option']
      [option_hash['option']].flatten.map { |hsh| PETFINDER_ADJECTIVES[hsh['$t']] }.compact.first
    else
      option_hash['$t']
    end
  end

  def get_petfinder_breed(breeds)
    if breeds['breed'].is_a?(Array)
      "#{breeds['breed'].map(&:values).flatten.join('/')} mix"
    else
      breeds['breed']['$t']
    end
  end

  def get_petharbor_sex(html_text)
    html_text =~ /female/i ? 'female' : 'male'
  end
end
