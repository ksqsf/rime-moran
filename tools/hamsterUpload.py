#!/usr/bin/env python3

from dotenv import load_dotenv
import os
import sys
import requests
import argparse
import datetime
import opencc

load_dotenv()

API_INPUT_SCHEMA = 'https://ihsiao.com/apps/hamster/auth/api/v1/input-schema'
API_ASSET = 'https://ihsiao.com/apps/hamster/auth/api/v1/input-schema/{schema_id}/asset'
API_REQUEST = 'https://ihsiao.com/apps/hamster/auth/api/v1/input-schema?limit=10&continuationMarker=&isASC=true'

headers = {
    'Authorization': os.getenv('HTTP_AUTHORIZATION'),
    'Hamster-Userid': os.getenv('HTTP_HAMSTER_USERID'),
    'Host': 'ihsiao.com',
    'Origin': 'https://ihsiao.com',
    'Referer': 'https://ihsiao.com/apps/hamster/manage/input-schema',
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
}

parser = argparse.ArgumentParser(
    prog='hamsterUpload',
    description='Upload assets to the Hamster input schema system',
)
parser.add_argument('schema_id')
parser.add_argument('path')
parser.add_argument('--variant', required=True, choices=['繁體','简体'])
args = parser.parse_args()

def requestSchemas():
    return requests.get(API_REQUEST, headers=headers).json()['records']

def findSchema(schemas, schema_id):
    for r in schemas:
        if r['recordName'] == schema_id:
            return r
    return None

def updateSchema(schemas, schema_id, title, author, desc, path):
    old = findSchema(schemas, schema_id)
    if not old:
        raise RuntimeError("schema_id " + schema_id + " not found")
    print(old)
    new = {
        'recordName': schema_id,
        'recordChangeTag': old['recordChangeTag'],
        'title': title or old['fields']['title']['value'],
        'author': author or old['fields']['author']['value'],
        'descriptions': desc or old['fields']['descriptions']['value'],  # [sic]
    }
    print('Updating schema metadata:', new)
    resp = requests.put(
        API_INPUT_SCHEMA,
        headers=headers,
        json=new
    )
    print('Update metadata result:', resp)
    with open(path, 'rb') as f:
        resp = requests.post(
            API_ASSET.format(schema_id=schema_id),
            headers=headers,
            files={'file': (os.path.basename(path), f, 'application/zip')}
        )
    print('Upload file:', resp)

schemas = requestSchemas()

cc = opencc.OpenCC('t2s.json')

DESC = f'''基於自然碼雙拼和輔助碼的 Rime 配置（{args.variant}版本）

GitHub 地址： https://github.com/ksqsf/rime-moran

本方案有八萬字庫、百萬詞庫，包含整句混輸輔助碼、詞語級直接輔助碼（輔篩模式）、四碼自動上屏（字詞模式）等多種輸入模式，含有諸多便捷輸入功能。

上傳時間：{datetime.datetime.now()}
'''

if args.variant == '简体':
    DESC = cc.convert(DESC)

updateSchema(
    schemas,
    args.schema_id,
    title=None, author=None, desc=DESC,
    path=args.path
)
